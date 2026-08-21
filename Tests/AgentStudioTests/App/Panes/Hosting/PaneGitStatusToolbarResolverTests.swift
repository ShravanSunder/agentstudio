import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@MainActor
@Suite("Pane Git status toolbar resolver")
struct PaneGitStatusToolbarResolverTests {
    @Test("resolves the pane's validated worktree keyed status")
    func resolvesValidatedWorktreeKeyedStatus() throws {
        let store = WorkspaceStore()
        let repoCache = RepoCacheAtom()
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/pane-git-status-toolbar"))
        let worktree = try #require(
            store.repos.first(where: { $0.id == repo.id })?.worktrees.first
        )
        let pane = store.createPane(
            launchDirectory: worktree.path,
            title: "Terminal",
            facets: PaneContextFacets(
                repoId: repo.id,
                worktreeId: worktree.id,
                cwd: worktree.path
            )
        )
        store.appendTab(Tab(paneId: pane.id))
        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: worktree.id,
                repoId: repo.id,
                branch: "feature/drawer-status",
                snapshot: GitWorkingTreeSnapshot(
                    worktreeId: worktree.id,
                    repoId: repo.id,
                    rootPath: worktree.path,
                    summary: GitWorkingTreeSummary(
                        changed: 2,
                        staged: 0,
                        untracked: 0,
                        linesAdded: 20,
                        linesDeleted: 14,
                        aheadCount: 0,
                        behindCount: 625,
                        hasUpstream: true
                    ),
                    branch: "feature/drawer-status"
                )
            )
        )

        let presentation = try #require(
            PaneGitStatusToolbarResolver.resolve(
                paneId: pane.id,
                store: store,
                repoCache: repoCache
            )
        )

        #expect(presentation.linesAdded == 20)
        #expect(presentation.linesDeleted == 14)
        #expect(presentation.commitsAhead == nil)
        #expect(presentation.commitsBehind == 625)
    }

    @Test("missing pane association and missing enrichment render no status")
    func missingAssociationAndEnrichmentRenderNoStatus() throws {
        let store = WorkspaceStore()
        let repoCache = RepoCacheAtom()
        let floatingPane = store.createPane(
            launchDirectory: URL(fileURLWithPath: "/tmp"),
            title: "Floating"
        )

        #expect(
            PaneGitStatusToolbarResolver.resolve(
                paneId: floatingPane.id,
                store: store,
                repoCache: repoCache
            ) == nil
        )

        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/pane-git-status-no-enrichment"))
        let worktree = try #require(
            store.repos.first(where: { $0.id == repo.id })?.worktrees.first
        )
        let worktreePane = store.createPane(
            launchDirectory: worktree.path,
            title: "Terminal",
            facets: PaneContextFacets(
                repoId: repo.id,
                worktreeId: worktree.id,
                cwd: worktree.path
            )
        )

        #expect(
            PaneGitStatusToolbarResolver.resolve(
                paneId: worktreePane.id,
                store: store,
                repoCache: repoCache
            ) == nil
        )
    }
}
