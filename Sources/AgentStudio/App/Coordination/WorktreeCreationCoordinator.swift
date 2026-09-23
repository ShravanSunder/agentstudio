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
    private let destinationProbe: WorktreeDestinationProbe
    private let presentFailure: @MainActor (WorktreeCreationFailure) -> Void
    private var inFlightDestinations: Set<URL> = []
    private var creationTasksByID: [UUID: Task<WorktreeCreationOutcome, Never>] = [:]

    init(
        topology: RepositoryTopologyAtom,
        gitClient: any WorktreeCreationGitClient,
        publication: any WorktreePublicationHolding,
        destinationProbe: WorktreeDestinationProbe = .live,
        presentFailure: @escaping @MainActor (WorktreeCreationFailure) -> Void
    ) {
        self.topology = topology
        self.gitClient = gitClient
        self.publication = publication
        self.destinationProbe = destinationProbe
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
        guard let source = resolveSource(request.sourceWorktreeId) else { return .failed(.sourceUnavailable) }
        let destination: WorktreeCreationDestination
        switch WorktreeDestinationPolicy.resolve(
            repositoryPath: source.repository.repoPath,
            branchName: request.branchName,
            watchedPaths: topology.watchedPaths,
            probe: destinationProbe
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
        let failure: WorktreeCreationFailure? =
            switch request.kind {
            case .cleanCheckout:
                await createCleanCheckout(source: source, destination: destination.path, branchName: request.branchName)
            case .fork:
                await forkSource(source: source, destination: destination.path, branchName: request.branchName)
            }
        await publication.releasePublicationHold(holdID)
        // Rescan after failure too: fresh discovery reconciles whatever a rolled-back or
        // partially cleaned creation left, rather than trusting earlier scan evidence.
        await publication.refreshWatchedFolder(destination.watchedPath.id, among: topology.watchedPaths)

        if let failure {
            return .failed(failure)
        }
        return .created(destination: destination.path)
    }

    /// `git worktree add` on a new branch that starts at the source worktree's HEAD.
    private func createCleanCheckout(
        source: (worktree: Worktree, repository: Repo),
        destination: URL,
        branchName: WorktreeBranchName
    ) async -> WorktreeCreationFailure? {
        do throws(GitDataPlaneError) {
            let headCommit = try await gitClient.headCommit(ofWorktreeAt: source.worktree.path)
            _ = try await gitClient.createWorktree(
                GitCreateWorktreeRequest(
                    repositoryPath: source.repository.repoPath,
                    destinationPath: destination,
                    mode: .newBranch(name: branchName.rawValue, startPoint: .named(headCommit))
                ))
            return nil
        } catch {
            return .gitFailure(error)
        }
    }

    /// Copy-on-write fork of the source's current files; the new branch starts at the
    /// source HEAD the SDK captures, so no start point is passed.
    private func forkSource(
        source: (worktree: Worktree, repository: Repo),
        destination: URL,
        branchName: WorktreeBranchName
    ) async -> WorktreeCreationFailure? {
        do throws(GitWorktreeForkError) {
            let result = try await gitClient.forkWorktree(
                GitForkWorktreeRequest(
                    sourceWorktreePath: source.worktree.path,
                    destinationPath: destination,
                    mode: .newBranch(name: branchName.rawValue)
                ))
            let report = result.materialization
            Self.logger.info(
                "Worktree fork materialized: cloned=\(report.clonedRegularFileCount) skipped=\(report.skippedEntries.count) normalized=\(report.normalizedEntries.count)"
            )
            return nil
        } catch {
            return .forkFailure(error)
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
