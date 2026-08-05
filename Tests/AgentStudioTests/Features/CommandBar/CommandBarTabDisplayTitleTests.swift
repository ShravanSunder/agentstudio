import AgentStudioCore
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCommandBar

@MainActor
@Suite(.serialized)
struct CommandBarTabDisplayTitleTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test
    func test_everythingScope_placeholderTabName_fallsBackToDerivedTitle() {
        let store = WorkspaceStore()

        let repo = store.addRepo(at: URL(filePath: "/tmp/commandbar-placeholder"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "feature-name",
            path: URL(filePath: "/tmp/commandbar-placeholder/feature-name")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: repo.worktrees + [worktree])
        guard let storedWorktree = store.repo(repo.id)?.worktrees.first(where: { $0.id == worktree.id }) else {
            Issue.record("Expected linked worktree")
            return
        }

        let repoCache = RepoCacheAtom()
        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: storedWorktree.id, repoId: repo.id, branch: "feature/pane-labels")
        )

        let pane = store.createPane(
            launchDirectory: storedWorktree.path,
            title: "Ignored",
            facets: PaneContextFacets(
                repoId: repo.id,
                repoName: repo.name,
                worktreeId: storedWorktree.id,
                worktreeName: storedWorktree.name,
                cwd: storedWorktree.path
            )
        )
        let tab = Tab(paneId: pane.id, name: "Tab")
        store.appendTab(tab)

        let items = CommandBarDataSource.items(
            scope: .everything,
            store: store,
            repoCache: repoCache,
            dispatcher: FakeAppCommandDispatcher()
        )
        let tabItem = items.first { $0.id == "tab-\(tab.id.uuidString)" }

        #expect(tabItem?.title == "feature-name · feature/pane-labels")
    }
}
