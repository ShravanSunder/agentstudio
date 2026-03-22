import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneDisplayProjectorTests {
    @Test
    func worktreeBackedPane_usesRepoBranchAndFolderLabel() {
        let store = WorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let repo = store.addRepo(at: URL(filePath: "/tmp/agent-studio"))
        let worktree = makeWorktree(
            repoId: repo.id,
            name: "feature-name",
            path: "/tmp/agent-studio/feature-name"
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktree.id, repoId: repo.id, branch: "feature/pane-labels")
        )

        let pane = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id),
            title: "Ignored Terminal Title",
            facets: PaneContextFacets(
                repoId: repo.id,
                repoName: "agent-studio",
                worktreeId: worktree.id,
                worktreeName: "feature-name",
                cwd: URL(fileURLWithPath: "/tmp/agent-studio/feature-name/src")
            )
        )

        let parts = PaneDisplayProjector.displayParts(for: pane, store: store, repoCache: repoCache)

        #expect(parts.primaryLabel == "agent-studio | feature/pane-labels | feature-name")
    }

    @Test
    func floatingPane_usesCwdFolderFallback() {
        let store = WorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let pane = store.createPane(
            source: .floating(workingDirectory: URL(fileURLWithPath: "/tmp/project-dev"), title: "ignored"),
            title: "ignored",
            facets: PaneContextFacets(cwd: URL(fileURLWithPath: "/tmp/project-dev"))
        )

        let parts = PaneDisplayProjector.displayParts(for: pane, store: store, repoCache: repoCache)

        #expect(parts.primaryLabel == "project-dev")
    }
}
