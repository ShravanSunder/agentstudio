import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("CommandBar pane search", .serialized)
struct CommandBarPaneSearchTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test
    func panesScopeTabKeywordsIncludeRepoAndWorktreeContextFromPanes() {
        let store = WorkspaceStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/search-agent-studio"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "pane-shortcuts",
            path: URL(filePath: "/tmp/search-agent-studio.pane-shortcuts")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        let pane = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Shell",
            facets: PaneContextFacets(
                repoId: repo.id,
                repoName: repo.name,
                worktreeId: worktree.id,
                worktreeName: worktree.name,
                cwd: worktree.path
            )
        )
        let tab = Tab(paneId: pane.id, name: "Review Tab")
        store.appendTab(tab)

        let items = CommandBarDataSource.items(
            scope: .panes,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: CommandDispatcher.shared
        )
        let tabItem = items.first { $0.id == "tab-\(tab.id.uuidString)" }

        #expect(tabItem?.keywords.contains("search-agent-studio") == true)
        #expect(tabItem?.keywords.contains("pane-shortcuts") == true)
        #expect(tabItem?.keywords.contains("Review Tab") == true)
    }

    @Test
    func panesScopeSearchFiltersPaneByRepoNameAndTabName() {
        let store = WorkspaceStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/filter-repo-name"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "filter-worktree",
            path: URL(filePath: "/tmp/filter-repo-name/filter-worktree")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        let pane = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Pane Shell",
            facets: PaneContextFacets(
                repoId: repo.id,
                repoName: repo.name,
                worktreeId: worktree.id,
                worktreeName: worktree.name,
                cwd: worktree.path
            )
        )
        store.appendTab(Tab(paneId: pane.id, name: "Operations"))

        let items = CommandBarDataSource.items(
            scope: .panes,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: CommandDispatcher.shared
        )

        #expect(
            CommandBarSearch.filter(items: items, query: "filter-repo-name").contains {
                $0.id == "pane-\(pane.id.uuidString)"
            })
        #expect(
            CommandBarSearch.filter(items: items, query: "Operations").contains {
                $0.id == "pane-\(pane.id.uuidString)"
            })
    }

    @Test("$ pane scope searches pane notes")
    func paneScopeSearchesPaneNotes() {
        let store = WorkspaceStore()
        var metadata = PaneMetadata(source: .floating(launchDirectory: nil, title: nil), title: "Terminal")
        metadata.updateNote("zmx lease repro")
        let pane = Pane(
            id: PaneId().uuid,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: metadata
        )
        #expect(store.paneAtom.insertRestoredPane(pane))
        store.appendTab(Tab(paneId: pane.id))

        let items = CommandBarDataSource.items(
            scope: .panes,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: CommandDispatcher.shared
        )

        #expect(
            items.contains { item in
                item.id == "pane-\(pane.id.uuidString)" && item.keywords.contains("zmx lease repro")
            })
    }
}
