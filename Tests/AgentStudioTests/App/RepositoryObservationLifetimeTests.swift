import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite("Repository observation lifetime", .serialized)
struct RepositoryObservationLifetimeTests {
    @Test("same-path reparenting invalidates PR projections in both surviving families")
    func reparentingInvalidatesBothFamilyCaches() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let store = WorkspaceStore()
            let root = URL(fileURLWithPath: "/tmp/lifetime-reparent")
            let watch = try #require(store.mutationCoordinator.addWatchedPath(root))
            let oldFamily = store.addRepo(at: root.appending(path: "old"))
            let newFamily = store.addRepo(at: root.appending(path: "new"))
            let linked = Worktree(
                id: UUIDv7.generate(), repoId: oldFamily.id, name: "linked", path: root.appending(path: "linked"))
            _ = store.mutationCoordinator.reconcileDiscoveredWorktrees(
                oldFamily.id, worktrees: oldFamily.worktrees + [linked])
            let cache = RepoCacheAtom()
            for family in [oldFamily, newFamily] {
                cache.setRepoEnrichment(.statusUnavailable(repoId: family.id, reason: "previous family scope"))
                let branchKey = try #require(RepoBranchKey(repoId: family.id, branch: "main"))
                cache.applyPullRequestFacts([branchKey: .init(openCount: 7, exactOpenURL: nil)])
            }
            let coordinator = WorkspaceCacheCoordinator(
                workspaceStore: store, repoCache: cache,
                validateSourceObservations: { _ in true }, scopeSyncHandler: { _ in })
            let observation = WatchedFolderTopologyObservation(
                root: root,
                registration: .init(
                    sourceID: .init(kind: .watchedParentMembership, rootID: watch.id),
                    registrationGeneration: 1, rootGeneration: 1),
                entries: [
                    .init(path: oldFamily.repoPath, kind: .cloneRoot, repositoryKey: oldFamily.repoPath.path),
                    .init(path: newFamily.repoPath, kind: .cloneRoot, repositoryKey: newFamily.repoPath.path),
                    .init(
                        path: linked.path, kind: .linkedWorktree(parentClonePath: newFamily.repoPath),
                        repositoryKey: newFamily.repoPath.path),
                ],
                otherObservedPaths: [],
                coverage: .additive,
                baselineMembershipRevision: store.repositoryTopologyAtom.worktreePathIndexGeneration,
                incompleteOtherScopes: []
            )

            await coordinator.consumeWatchedFolderObservation(observation, sequence: 1)

            #expect(store.repositoryTopologyAtom.worktree(linked.id)?.repoId == newFamily.id)
            #expect(cache.pullRequestFactsSnapshot().isEmpty)
            for family in [oldFamily, newFamily] {
                #expect(
                    cache.repoEnrichment(for: family.id)
                        == .statusUnavailable(repoId: family.id, reason: "previous family scope"))
            }
            await coordinator.shutdown()
        }
    }

    @Test("a queued snapshot from before hide and return cannot publish into the reused checkout ID")
    func lateSnapshotCannotCrossAvailabilityLifetime() throws {
        try withTestCoreAtoms { _ in
            let store = WorkspaceStore()
            let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/lifetime-repository"))
            let worktree = try #require(repo.worktrees.first)
            let cache = RepoCacheAtom()
            let coordinator = WorkspaceCacheCoordinator(
                workspaceStore: store, repoCache: cache, scopeSyncHandler: { _ in })
            let old = WorktreeEnvelope.test(
                event: .gitWorkingDirectory(
                    .snapshotChanged(
                        snapshot: .init(
                            worktreeId: worktree.id, repoId: repo.id, rootPath: worktree.path,
                            summary: .init(changed: 7, staged: 0, untracked: 0), branch: "obsolete"
                        ))),
                repoId: repo.id,
                worktreeId: worktree.id,
                source: .system(.builtin(.gitWorkingDirectoryProjector)),
                observationLifetime: .worktree(
                    try #require(store.repositoryTopologyAtom.worktreeObservationLifetimes[worktree.id]))
            )
            #expect(
                store.mutationCoordinator.recordRepositoryAbsence(
                    repo.id,
                    at: .init(utc: Date(timeIntervalSince1970: 1_700_000_000), bootID: "fixture", uptimeNanoseconds: 1)
                ))
            #expect(store.mutationCoordinator.restoreObservedWorktrees([worktree.id]))

            coordinator.handleEnrichment(old)

            #expect(cache.worktreeEnrichment(for: worktree.id) == nil)
            #expect(store.repositoryTopologyAtom.worktree(worktree.id)?.id == worktree.id)
        }
    }
}
