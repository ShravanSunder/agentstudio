import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct CommandBarUnifiedWorktreeDataSourceTests {
    init() {
        installTestAtomScopeIfNeeded()
    }

    private let dispatcher = CommandDispatcher.shared

    private func makeStore() -> WorkspaceStore {
        WorkspaceStore()
    }

    @Test
    func test_everythingScope_worktreeItemsHavePresenceState() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/everything-wt"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/everything-wt"),
            isMainWorktree: true
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        guard let storedWorktree = store.repos.first?.worktrees.first else {
            Issue.record("Expected stored worktree")
            return
        }
        let pane = store.createPane(
            source: .worktree(
                worktreeId: storedWorktree.id,
                repoId: repo.id,
                launchDirectory: storedWorktree.path
            ),
            title: "Terminal"
        )
        store.appendTab(Tab(paneId: pane.id))

        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        let worktreeItem = items.first { $0.title == "main" && $0.group == "Worktrees" }
        #expect(worktreeItem != nil)
        #expect(worktreeItem?.worktreeOpenState == .singlePane)
        #expect(worktreeItem?.group == "Worktrees")
    }

    @Test
    func test_everythingScope_paneItemsStillPresent() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/everything-panes"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/everything-panes"),
            isMainWorktree: true
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        guard let storedWorktree = store.repos.first?.worktrees.first else {
            Issue.record("Expected stored worktree")
            return
        }
        let pane = store.createPane(
            source: .worktree(
                worktreeId: storedWorktree.id,
                repoId: repo.id,
                launchDirectory: storedWorktree.path
            ),
            title: "Terminal"
        )
        store.appendTab(Tab(paneId: pane.id))

        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        let paneItems = items.filter { $0.id.hasPrefix("pane-") }
        #expect(paneItems.count == 1)
        #expect(paneItems[0].id == "pane-\(pane.id.uuidString)")
    }

    @Test
    func test_everythingScope_tabItemsStillPresent() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/everything-tabs"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/everything-tabs"),
            isMainWorktree: true
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        guard let storedWorktree = store.repos.first?.worktrees.first else {
            Issue.record("Expected stored worktree")
            return
        }
        let pane = store.createPane(
            source: .worktree(
                worktreeId: storedWorktree.id,
                repoId: repo.id,
                launchDirectory: storedWorktree.path
            ),
            title: "Terminal"
        )
        store.appendTab(Tab(paneId: pane.id))

        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        let tabItems = items.filter { $0.id.hasPrefix("tab-") }
        #expect(tabItems.count == 1)
    }

    @Test
    func test_everythingScope_worktreeItemsUseUnifiedIds() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/everything-wt-id"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "feature",
            path: URL(filePath: "/tmp/everything-wt-id/feature")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])

        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        let oldStyleItems = items.filter {
            $0.id.hasPrefix("wt-") && !$0.id.hasPrefix("wt-choice-") && !$0.id.hasPrefix("wt-new-")
                && !$0.id.hasPrefix("wt-add-") && !$0.id.hasPrefix("wt-pane-")
        }
        let unifiedItem = items.first { $0.id == "repo-wt-\(worktree.id.uuidString)" }

        #expect(oldStyleItems.isEmpty)
        #expect(unifiedItem != nil)
    }

    @Test
    func test_everythingScope_tabKeywordsIncludeArrangementNames() {
        let store = makeStore()
        let pane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
        var tab = Tab(paneId: pane.id)
        let namedArrangement = PaneArrangement(
            name: "Review",
            isDefault: false,
            layout: tab.layout,
            visiblePaneIds: Set(tab.activePaneIds)
        )
        tab.arrangements.append(namedArrangement)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let tabItem = items.first { $0.id == "tab-\(tab.id.uuidString)" }

        #expect(tabItem?.keywords.contains("Review") == true)
    }

    @Test
    func test_everythingScope_tabKeywordsIncludeTabName() {
        let store = makeStore()
        let pane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id, name: "My Workspace")
        store.appendTab(tab)

        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let tabItem = items.first { $0.id == "tab-\(tab.id.uuidString)" }

        #expect(tabItem?.keywords.contains("My Workspace") == true)
    }

    @Test
    func test_reposScope_worktreeWithNoPanes_hasNotOpenState() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/repo-no-panes"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/repo-no-panes"),
            isMainWorktree: true
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])

        let items = CommandBarDataSource.items(
            scope: .repos, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        let item = items.first { $0.title == "main" && $0.group == "Repos" }
        #expect(item != nil)
        #expect(item?.worktreeOpenState == .notOpen)
        #expect(item?.hasChildren == true)
    }

    @Test
    func test_reposScope_worktreeWithOnePane_hasSinglePaneState() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/repo-one-pane"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "feature",
            path: URL(filePath: "/tmp/repo-one-pane/feature")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        guard let storedWorktree = store.repos.first?.worktrees.first else {
            Issue.record("Expected stored worktree")
            return
        }
        let pane = store.createPane(
            source: .worktree(
                worktreeId: storedWorktree.id,
                repoId: repo.id,
                launchDirectory: storedWorktree.path
            ),
            title: "Terminal"
        )
        store.appendTab(Tab(paneId: pane.id))

        let items = CommandBarDataSource.items(
            scope: .repos, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        let item = items.first { $0.id == "repo-wt-\(storedWorktree.id.uuidString)" }
        #expect(item?.worktreeOpenState == .singlePane)
        #expect(item?.subtitle?.contains("Tab 1") == true)
        #expect(item?.hasChildren == true)
        guard let item else {
            Issue.record("Expected unified worktree item")
            return
        }
        guard case .worktreeAction(let presence) = item.action else {
            Issue.record("Expected worktreeAction for single-pane worktree")
            return
        }
        #expect(presence.worktreeId == storedWorktree.id)
    }

    @Test
    func test_reposScope_worktreeWithMultiplePanes_hasMultiplePanesState() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/repo-multi-pane"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/repo-multi-pane"),
            isMainWorktree: true
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        guard let storedWorktree = store.repos.first?.worktrees.first else {
            Issue.record("Expected stored worktree")
            return
        }

        let paneA = store.createPane(
            source: .worktree(
                worktreeId: storedWorktree.id,
                repoId: repo.id,
                launchDirectory: storedWorktree.path
            ),
            title: "A"
        )
        store.appendTab(Tab(paneId: paneA.id))
        let paneB = store.createPane(
            source: .worktree(
                worktreeId: storedWorktree.id,
                repoId: repo.id,
                launchDirectory: storedWorktree.path
            ),
            title: "B"
        )
        store.appendTab(Tab(paneId: paneB.id))

        let items = CommandBarDataSource.items(
            scope: .repos, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        let item = items.first { $0.id == "repo-wt-\(storedWorktree.id.uuidString)" }
        #expect(item?.worktreeOpenState == .multiplePanes)
        #expect(item?.subtitle?.contains("2 panes") == true)
        #expect(item?.hasChildren == true)
        guard let item else {
            Issue.record("Expected unified worktree item")
            return
        }
        guard case .worktreeAction(let presence) = item.action else {
            Issue.record("Expected worktreeAction for multi-pane worktree")
            return
        }
        #expect(presence.openState == .multiplePanes)
    }

    @Test
    func test_reposScope_worktreeWithOnePaneSubtitleShowsTabLocation() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/repo-subtitle"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/repo-subtitle"),
            isMainWorktree: true
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        guard let storedWorktree = store.repos.first?.worktrees.first else {
            Issue.record("Expected stored worktree")
            return
        }
        let pane = store.createPane(
            source: .worktree(
                worktreeId: storedWorktree.id,
                repoId: repo.id,
                launchDirectory: storedWorktree.path
            ),
            title: "T"
        )
        store.appendTab(Tab(paneId: pane.id))

        let items = CommandBarDataSource.items(
            scope: .repos, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let item = items.first { $0.id == "repo-wt-\(storedWorktree.id.uuidString)" }

        #expect(item?.subtitle == "● Tab 1 · 1 pane")
    }
}
