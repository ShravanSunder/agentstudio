import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite(.serialized)
@MainActor
final class WorkspaceCacheCoordinatorOriginTests {
    @Test
    func enrichment_originChanged_clearsCachedPullRequestFacts() {
        let workspaceStore = WorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )

        let repo = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/luna-origin-change-cache"))
        let worktree = Worktree(repoId: repo.id, name: "main", path: repo.repoPath, isMainWorktree: true)
        workspaceStore.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktree.id, repoId: repo.id, branch: "main")
        )
        repoCache.setPullRequestCount(1, for: worktree.id)
        repoCache.setPullRequestURL(
            URL(string: "https://github.com/old-owner/old-repo/pull/1")!,
            for: worktree.id
        )

        coordinator.handleEnrichment(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(
                    .originChanged(
                        repoId: repo.id,
                        from: "git@github.com:old-owner/old-repo.git",
                        to: "git@github.com:new-owner/new-repo.git"
                    )
                ),
                repoId: repo.id,
                worktreeId: worktree.id,
                source: .system(.builtin(.gitWorkingDirectoryProjector))
            )
        )

        #expect(repoCache.pullRequestCount(for: worktree.id) == nil)
        #expect(repoCache.pullRequestURL(for: worktree.id) == nil)
    }

    @Test
    func enrichment_originUnavailable_clearsCachedPullRequestFacts() {
        let workspaceStore = WorkspaceStore()
        let repoCache = RepoCacheAtom()
        let coordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )

        let repo = workspaceStore.addRepo(at: URL(fileURLWithPath: "/tmp/luna-origin-unavailable-cache"))
        let worktree = Worktree(repoId: repo.id, name: "main", path: repo.repoPath, isMainWorktree: true)
        workspaceStore.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktree.id, repoId: repo.id, branch: "main")
        )
        repoCache.setPullRequestCount(1, for: worktree.id)
        repoCache.setPullRequestURL(
            URL(string: "https://github.com/old-owner/old-repo/pull/1")!,
            for: worktree.id
        )

        coordinator.handleEnrichment(
            WorktreeEnvelope.test(
                event: .gitWorkingDirectory(.originUnavailable(repoId: repo.id)),
                repoId: repo.id,
                worktreeId: worktree.id,
                source: .system(.builtin(.gitWorkingDirectoryProjector))
            )
        )

        #expect(repoCache.pullRequestCount(for: worktree.id) == nil)
        #expect(repoCache.pullRequestURL(for: worktree.id) == nil)
    }
}
