import AgentStudioGit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

/// Order ledger for the creation sequence. Real publication and real Git are proven by
/// `WatchedFolderPublicationHoldIntegrationTests` and `WorktreeCreationEndToEndTests`.
@MainActor
@Suite("Worktree creation coordinator", .serialized)
struct WorktreeCreationCoordinatorTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("success holds, creates from the source HEAD, releases, then rescans the owning watched folder")
    func successOrdersHoldCreateReleaseRefresh() async throws {
        let fixture = try Self.makeFixture()
        let ledger = CreationLedger()
        let presented = PresentedFailures()
        let coordinator = Self.makeCoordinator(fixture: fixture, ledger: ledger, presented: presented)

        let outcome = await coordinator.create(try fixture.request(branch: "feat/ledger")).value

        let destination = fixture.watchedRoot.appending(path: "repo.feat-ledger", directoryHint: .isDirectory)
            .standardizedFileURL
        #expect(outcome == .created(destination: destination))
        #expect(
            await ledger.events == [
                .hold(destination),
                .headCommit(fixture.worktree.path),
                .create(
                    GitCreateWorktreeRequest(
                        repositoryPath: fixture.repository.repoPath,
                        destinationPath: destination,
                        mode: .newBranch(name: "feat/ledger", startPoint: .named(FakeWorktreeCreationGitClient.head))
                    )),
                .release,
                .refresh(fixture.watchedPath.id),
            ])
        #expect(presented.failures.isEmpty)
    }

    @Test("an SDK failure releases the hold, skips the rescan, and presents the failure")
    func sdkFailureReleasesHoldAndPresents() async throws {
        let fixture = try Self.makeFixture()
        let ledger = CreationLedger()
        let presented = PresentedFailures()
        let gitError = GitDataPlaneError.libgit2Failure(code: -4, klass: 7, message: "reference already exists")
        let coordinator = Self.makeCoordinator(
            fixture: fixture, ledger: ledger, presented: presented, createError: gitError)

        let outcome = await coordinator.create(try fixture.request(branch: "feat/exists")).value

        #expect(outcome == .failed(.gitFailure(gitError)))
        let events = await ledger.events
        #expect(events.first.map { if case .hold = $0 { true } else { false } } == true)
        #expect(events.last == .release)
        #expect(!events.contains { if case .refresh = $0 { true } else { false } })
        #expect(presented.failures == [.gitFailure(gitError)])
    }

    @Test("a destination rejection never holds or reaches the SDK")
    func destinationRejectionTouchesNothing() async throws {
        let fixture = try Self.makeFixture()
        let ledger = CreationLedger()
        let presented = PresentedFailures()
        let destination = fixture.watchedRoot.appending(path: "repo.taken", directoryHint: .isDirectory)
            .standardizedFileURL
        let coordinator = Self.makeCoordinator(
            fixture: fixture, ledger: ledger, presented: presented, existingPaths: [destination])

        let outcome = await coordinator.create(try fixture.request(branch: "taken")).value

        #expect(outcome == .failed(.destinationRejected(.destinationExists(destination))))
        #expect(await ledger.events.isEmpty)
        #expect(presented.failures == [.destinationRejected(.destinationExists(destination))])
    }

    @Test("a fork request is unavailable until the SDK fork lands")
    func forkIsUnavailable() async throws {
        let fixture = try Self.makeFixture()
        let ledger = CreationLedger()
        let presented = PresentedFailures()
        let coordinator = Self.makeCoordinator(fixture: fixture, ledger: ledger, presented: presented)

        let outcome = await coordinator.create(try fixture.request(branch: "fork", kind: .fork)).value

        #expect(outcome == .failed(.forkUnavailable))
        #expect(await ledger.events.isEmpty)
        #expect(coordinator.canCreate(fromWorktree: fixture.worktree.id))
    }

    // MARK: - Fixtures

    private struct Fixture {
        let store: WorkspaceStore
        let watchedRoot: URL
        let watchedPath: WatchedPath
        let repository: Repo
        let worktree: Worktree

        func request(branch: String, kind: WorktreeCreationKind = .cleanCheckout) throws -> WorktreeCreationRequest {
            WorktreeCreationRequest(
                kind: kind,
                sourceWorktreeId: worktree.id,
                branchName: try WorktreeBranchName.validated(branch).get()
            )
        }
    }

    private static func makeFixture() throws -> Fixture {
        let store = WorkspaceStore()
        let watchedRoot = URL(
            filePath: "/Users/dev/coordinator-\(UUIDv7.generate().uuidString)", directoryHint: .isDirectory)
        let watchedPath = try #require(store.mutationCoordinator.addWatchedPath(watchedRoot))
        let repositoryPath = watchedRoot.appending(path: "repo", directoryHint: .isDirectory)
        let repository = store.addRepo(at: repositoryPath)
        let mainWorktree = Worktree(repoId: repository.id, name: "repo", path: repositoryPath, isMainWorktree: true)
        store.reconcileDiscoveredWorktrees(repository.id, worktrees: [mainWorktree])
        let resolvedRepository = try #require(store.repositoryTopologyAtom.repo(repository.id))
        let mainWorktreeMatch = resolvedRepository.worktrees.first { $0.isMainWorktree }
        let worktree = try #require(mainWorktreeMatch)
        return Fixture(
            store: store,
            watchedRoot: watchedRoot,
            watchedPath: watchedPath,
            repository: resolvedRepository,
            worktree: worktree
        )
    }

    private static func makeCoordinator(
        fixture: Fixture,
        ledger: CreationLedger,
        presented: PresentedFailures,
        createError: GitDataPlaneError? = nil,
        existingPaths: Set<URL> = []
    ) -> WorktreeCreationCoordinator {
        WorktreeCreationCoordinator(
            topology: fixture.store.repositoryTopologyAtom,
            gitClient: FakeWorktreeCreationGitClient(ledger: ledger, createError: createError),
            publication: FakeWorktreePublication(ledger: ledger),
            pathExists: { existingPaths.contains($0.standardizedFileURL) },
            presentFailure: { presented.failures.append($0) }
        )
    }
}

private enum CreationEvent: Equatable {
    case hold(URL)
    case headCommit(URL)
    case create(GitCreateWorktreeRequest)
    case release
    case refresh(UUID)
}

private actor CreationLedger {
    private(set) var events: [CreationEvent] = []

    func record(_ event: CreationEvent) {
        events.append(event)
    }
}

@MainActor
private final class PresentedFailures {
    var failures: [WorktreeCreationFailure] = []
}

private struct FakeWorktreeCreationGitClient: WorktreeCreationGitClient {
    static let head = "0123456789abcdef0123456789abcdef01234567"
    let ledger: CreationLedger
    let createError: GitDataPlaneError?

    func headCommit(ofWorktreeAt worktreePath: URL) async throws(GitDataPlaneError) -> String {
        await ledger.record(.headCommit(worktreePath))
        return Self.head
    }

    func createWorktree(_ request: GitCreateWorktreeRequest) async throws(GitDataPlaneError) -> GitWorktreeSnapshot {
        await ledger.record(.create(request))
        if let createError { throw createError }
        return GitWorktreeSnapshot(
            id: GitWorktreeID(rawValue: request.destinationPath.lastPathComponent),
            repositoryID: GitRepositoryID(rawValue: request.repositoryPath.path),
            displayName: request.destinationPath.lastPathComponent,
            path: request.destinationPath,
            canonicalPath: request.destinationPath,
            gitDirectory: request.destinationPath.appending(path: ".git"),
            indexPath: request.destinationPath.appending(path: ".git/index"),
            isMainWorktree: false,
            isLocked: false,
            lockReason: nil,
            head: nil
        )
    }
}

private final class FakeWorktreePublication: WorktreePublicationHolding {
    let ledger: CreationLedger

    init(ledger: CreationLedger) {
        self.ledger = ledger
    }

    func holdPublication(of destination: URL) async -> WatchedFolderPublicationHoldID {
        await ledger.record(.hold(destination))
        return WatchedFolderPublicationHoldID(rawValue: UUIDv7.generate())
    }

    func releasePublicationHold(_: WatchedFolderPublicationHoldID) async {
        await ledger.record(.release)
    }

    func refreshWatchedFolder(_ watchedPathID: UUID, among _: [WatchedPath]) async {
        await ledger.record(.refresh(watchedPathID))
    }
}
