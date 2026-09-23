import Foundation
import Observation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

/// First interaction of the whole New Worktree path: dispatcher, shell owner,
/// creation coordinator, the Git SDK, the FilesystemActor hold and rescan, and
/// watched-folder discovery into `repositoryTopologyAtom`. Only FSEvents delivery
/// is controlled; scanning, Git, and topology application are production code.
@MainActor
@Suite("Worktree creation end to end", .serialized)
struct WorktreeCreationEndToEndTests {
    @Test("New Worktree from the dispatcher creates a linked worktree that discovery publishes")
    func newWorktreeReachesTopologyThroughDiscovery() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            // Arrange
            let fixture = try await EndToEndFixture.make()
            defer { fixture.remove() }
            let system = EndToEndSystem.make(repoCache: atoms.repoCache)
            do {
                await system.cacheCoordinator.startConsuming()
                let watchedPath = try #require(system.store.mutationCoordinator.addWatchedPath(fixture.watchedRoot))
                _ = await system.pipeline.refreshWatchedFolders([watchedPath])
                await awaitTopology(system.store) { mainWorktree(in: system.store, fixture: fixture) != nil }
                let source = try #require(mainWorktree(in: system.store, fixture: fixture))
                let delegate = AppDelegate()
                delegate.store = system.store
                delegate.installWorktreeCreationCoordinator(publication: system.pipeline)
                let request = WorktreeCreationRequest(
                    kind: .cleanCheckout,
                    sourceWorktreeId: source.id,
                    branchName: try WorktreeBranchName.validated("feat/end-to-end").get()
                )

                // Act
                let accepted = try await withIsolatedCommandDispatcher(
                    configure: { AppCommandDispatcher.shared.appCommandRouter = delegate },
                    body: { AppCommandDispatcher.shared.dispatchWorktreeCreation(request) }
                )
                await delegate.worktreeCreationCoordinator?.waitUntilIdle()
                await awaitTopology(system.store) { linkedWorktree(in: system.store, fixture: fixture) != nil }

                // Assert
                #expect(accepted)
                let created = try #require(linkedWorktree(in: system.store, fixture: fixture))
                #expect(system.store.repositoryTopologyAtom.repo(containing: created.id)?.id == source.repoId)
                #expect(FileManager.default.fileExists(atPath: fixture.destination.appending(path: "README.md").path))
                let branch = try await FilesystemTestGitRepo.runGit(
                    at: fixture.destination, args: ["rev-parse", "--abbrev-ref", "HEAD"])
                #expect(branch.trimmingCharacters(in: .whitespacesAndNewlines) == "feat/end-to-end")
                let destinationHead = try await FilesystemTestGitRepo.runGit(
                    at: fixture.destination, args: ["rev-parse", "HEAD"])
                #expect(destinationHead == fixture.sourceHead)
            } catch {
                await system.shutdown()
                throw error
            }
            await system.shutdown()
        }
    }
}

@MainActor
private func mainWorktree(in store: WorkspaceStore, fixture: EndToEndFixture) -> Worktree? {
    store.repositoryTopologyAtom.repos.flatMap(\.worktrees).first {
        canonicalPath($0.path) == canonicalPath(fixture.repositoryPath)
    }
}

@MainActor
private func linkedWorktree(in store: WorkspaceStore, fixture: EndToEndFixture) -> Worktree? {
    store.repositoryTopologyAtom.repos.flatMap(\.worktrees).first {
        canonicalPath($0.path) == canonicalPath(fixture.destination)
            && !store.repositoryTopologyAtom.isWorktreeUnavailable($0.id)
    }
}

/// Awaits observed topology changes until the predicate holds. Each wake is a
/// topology mutation, never a scheduler turn or a clock.
@MainActor
private func awaitTopology(_ store: WorkspaceStore, until predicate: @escaping @MainActor () -> Bool) async {
    while !predicate() {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            withObservationTracking {
                _ = store.repositoryTopologyAtom.repos
                _ = predicate()
            } onChange: {
                continuation.resume()
            }
        }
    }
}

/// Canonical path text; URL equality would also compare a trailing slash that
/// `URL(fileURLWithPath:)` adds only once the directory exists.
private func canonicalPath(_ url: URL) -> String {
    FilesystemRootOwnership.canonicalizeKernelPath(url.standardizedFileURL.path)
}

@MainActor
private struct EndToEndSystem {
    let store: WorkspaceStore
    let pipeline: FilesystemGitPipeline
    let cacheCoordinator: WorkspaceCacheCoordinator

    static func make(repoCache: RepoCacheAtom) -> Self {
        let bus = EventBus<RuntimeEnvelope>()
        let store = WorkspaceStore()
        let pipeline = FilesystemGitPipeline(
            bus: bus,
            gitWorkingTreeProvider: .stub { _ in nil },
            forgeStatusProvider: .stub { _ in .complete([]) },
            fseventStreamClient: ControllableFSEventStreamClient(),
            gitCoalescingWindow: .zero,
            gitRefreshPolicy: AppPolicies.GitRefresh.Policy()
        )
        let cacheCoordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: store,
            repoCache: repoCache,
            // Mirrors production boot: observations and retention refreshes are
            // validated against the same pipeline that produced them.
            refreshRetentionScopes: { [weak pipeline] paths, repositories, revision, scopeIDs in
                guard let pipeline else { return [] }
                return await pipeline.refreshForRepositoryRetention(
                    watchedPaths: paths, repositories: repositories, membershipRevision: revision, scanning: scopeIDs
                )
            },
            validateSourceObservations: { [weak pipeline] observations in
                guard let pipeline else { return false }
                return await pipeline.areCurrentWatchedFolderObservations(observations)
            },
            scopeSyncHandler: { [weak pipeline] scopeChange in
                await pipeline?.applyScopeChange(scopeChange)
            },
            enrichmentApplyTickCadence: .zero
        )
        return Self(store: store, pipeline: pipeline, cacheCoordinator: cacheCoordinator)
    }

    func shutdown() async {
        await cacheCoordinator.shutdown()
        await pipeline.shutdown()
    }
}

private struct EndToEndFixture {
    let watchedRoot: URL
    let repositoryPath: URL
    let destination: URL
    let sourceHead: String

    static func make() async throws -> Self {
        let watchedRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "tmp/worktree-creation-e2e-tests/\(UUIDv7.generate().uuidString)")
            .standardizedFileURL
        let repositoryPath = watchedRoot.appending(path: "repo")
        try FileManager.default.createDirectory(at: repositoryPath, withIntermediateDirectories: true)
        try "# fixture\n".write(to: repositoryPath.appending(path: "README.md"), atomically: true, encoding: .utf8)
        for args in [
            ["init"], ["symbolic-ref", "HEAD", "refs/heads/main"],
            ["config", "user.email", "luna-tests@example.com"], ["config", "user.name", "Luna Tests"],
            ["config", "commit.gpgsign", "false"], ["add", "README.md"], ["commit", "-m", "Initial commit"],
        ] {
            try await FilesystemTestGitRepo.runGit(at: repositoryPath, args: args)
        }
        let sourceHead = try await FilesystemTestGitRepo.runGit(at: repositoryPath, args: ["rev-parse", "HEAD"])
        return Self(
            watchedRoot: watchedRoot,
            repositoryPath: repositoryPath,
            destination: watchedRoot.appending(path: "repo.feat-end-to-end"),
            sourceHead: sourceHead
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: watchedRoot)
    }
}
