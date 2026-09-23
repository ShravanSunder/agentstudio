import AgentStudioCore
import AgentStudioGit
import AgentStudioInfrastructure
import Foundation
import os

enum WorktreeCreationOutcome: Equatable, Sendable {
    case created(destination: URL)
    case failed(WorktreeCreationFailure)
}

/// Sequences one worktree creation across the topology, the watched-folder publication
/// hold, and the Git SDK: resolve source and destination, hold the destination out of
/// discovery, create, release, then rescan the one watched folder that owns it. The new
/// worktree reaches the sidebar only through that discovery, never by insertion here.
@MainActor
final class WorktreeCreationCoordinator {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "WorktreeCreationCoordinator")

    private let topology: RepositoryTopologyAtom
    private let gitClient: any WorktreeCreationGitClient
    private let publication: any WorktreePublicationHolding
    private let pathExists: @Sendable (URL) -> Bool
    private let presentFailure: @MainActor (WorktreeCreationFailure) -> Void
    private var inFlightDestinations: Set<URL> = []
    private var creationTasksByID: [UUID: Task<WorktreeCreationOutcome, Never>] = [:]

    init(
        topology: RepositoryTopologyAtom,
        gitClient: any WorktreeCreationGitClient,
        publication: any WorktreePublicationHolding,
        pathExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        presentFailure: @escaping @MainActor (WorktreeCreationFailure) -> Void
    ) {
        self.topology = topology
        self.gitClient = gitClient
        self.publication = publication
        self.pathExists = pathExists
        self.presentFailure = presentFailure
    }

    func canCreate(fromWorktree worktreeId: UUID) -> Bool {
        resolveSource(worktreeId) != nil
    }

    /// Accepts a creation; the returned task finishes once the worktree is published or
    /// the failure has been presented.
    @discardableResult
    func create(_ request: WorktreeCreationRequest) -> Task<WorktreeCreationOutcome, Never> {
        let creationID = UUIDv7.generate()
        let task = Task { @MainActor [weak self] () -> WorktreeCreationOutcome in
            guard let self else { return .failed(.sourceUnavailable) }
            let outcome = await self.performCreation(request)
            self.creationTasksByID.removeValue(forKey: creationID)
            switch outcome {
            case .created(let destination):
                Self.logger.info("Worktree created at \(destination.path, privacy: .private)")
            case .failed(let failure):
                self.presentFailure(failure)
            }
            return outcome
        }
        creationTasksByID[creationID] = task
        return task
    }

    /// Returns once every creation accepted before the call has published or failed.
    func waitUntilIdle() async {
        for task in Array(creationTasksByID.values) {
            _ = await task.value
        }
    }

    private func performCreation(_ request: WorktreeCreationRequest) async -> WorktreeCreationOutcome {
        guard case .cleanCheckout = request.kind else { return .failed(.forkUnavailable) }
        guard let source = resolveSource(request.sourceWorktreeId) else { return .failed(.sourceUnavailable) }
        let destination: WorktreeCreationDestination
        switch WorktreeDestinationPolicy.resolve(
            repositoryPath: source.repository.repoPath,
            branchName: request.branchName,
            watchedPaths: topology.watchedPaths,
            pathExists: pathExists
        ) {
        case .success(let resolvedDestination):
            destination = resolvedDestination
        case .failure(let rejection):
            return .failed(.destinationRejected(rejection))
        }
        guard inFlightDestinations.insert(destination.path).inserted else {
            return .failed(.alreadyInProgress(destination: destination.path))
        }
        defer { inFlightDestinations.remove(destination.path) }

        let holdID = await publication.holdPublication(of: destination.path)
        let creationResult: Result<Void, GitDataPlaneError>
        do throws(GitDataPlaneError) {
            let headCommit = try await gitClient.headCommit(ofWorktreeAt: source.worktree.path)
            _ = try await gitClient.createWorktree(
                GitCreateWorktreeRequest(
                    repositoryPath: source.repository.repoPath,
                    destinationPath: destination.path,
                    mode: .newBranch(name: request.branchName.rawValue, startPoint: .named(headCommit))
                ))
            creationResult = .success(())
        } catch {
            creationResult = .failure(error)
        }
        await publication.releasePublicationHold(holdID)

        switch creationResult {
        case .failure(let error):
            return .failed(.gitFailure(error))
        case .success:
            await publication.refreshWatchedFolder(destination.watchedPath.id, among: topology.watchedPaths)
            return .created(destination: destination.path)
        }
    }

    private func resolveSource(_ worktreeId: UUID) -> (worktree: Worktree, repository: Repo)? {
        guard
            let worktree = topology.worktree(worktreeId),
            let repository = topology.repo(containing: worktreeId),
            !topology.isWorktreeUnavailable(worktreeId),
            !topology.isRepoUnavailable(repository.id)
        else { return nil }
        return (worktree, repository)
    }
}
