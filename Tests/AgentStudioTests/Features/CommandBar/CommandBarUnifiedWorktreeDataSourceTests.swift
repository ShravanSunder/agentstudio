import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct CommandBarUnifiedWorktreeDataSourceTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private let dispatcher = AppCommandDispatcher.shared

    private func makeStore() -> WorkspaceStore {
        WorkspaceStore()
    }

    @Test
    func test_reposScope_rootRowsAreReposNotWorktrees() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/root-agent-studio"))
        let main = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/root-agent-studio"),
            isMainWorktree: true
        )
        let feature = Worktree(
            repoId: repo.id,
            name: "pane-shortcuts",
            path: URL(filePath: "/tmp/root-agent-studio.pane-shortcuts")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [main, feature])

        let items = CommandBarDataSource.items(
            scope: .repos,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: dispatcher
        )

        #expect(items.contains { $0.id == "repo-\(repo.id.uuidString)" })
        #expect(!items.contains { $0.id == "repo-wt-\(main.id.uuidString)" })
        #expect(!items.contains { $0.id == "repo-wt-\(feature.id.uuidString)" })

        let repoItem = items.first { $0.id == "repo-\(repo.id.uuidString)" }
        #expect(repoItem?.title == "root-agent-studio")
        #expect(repoItem?.subtitle == "2 worktrees")
        #expect(repoItem?.hasChildren == true)
        #expect(repoItem?.group == "Repos")
    }

    @Test
    func test_reposScope_singleWorktreeRepoStillDrillsIn() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/single-root-repo"))

        let items = CommandBarDataSource.items(
            scope: .repos,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: dispatcher
        )

        let repoItem = items.first { $0.id == "repo-\(repo.id.uuidString)" }
        #expect(repoItem?.title == "single-root-repo")
        #expect(repoItem?.hasChildren == true)

        guard case .navigateRepo(let level) = repoItem?.action else {
            Issue.record("Expected repo root row to navigate")
            return
        }
        #expect(level.title == "single-root-repo")
        #expect(level.scopeLabel == "Repo")
    }

    @Test
    func test_reposScope_keywordsIncludeRepoAndWorktreeTags() throws {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/tagged-command-repo"))
        let main = try #require(store.repos.first?.worktrees.first)
        try store.repositoryTopologyAtom.setRepoTags(["client-alpha"], repoId: repo.id)
        try store.repositoryTopologyAtom.setWorktreeTags(["review-slice"], worktreeId: main.id)

        let items = CommandBarDataSource.items(
            scope: .repos,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: dispatcher
        )

        let repoItem = try #require(items.first { $0.id == "repo-\(repo.id.uuidString)" })
        #expect(repoItem.keywords.contains("client-alpha"))
        #expect(repoItem.keywords.contains("review-slice"))
        guard case .navigateRepo(let level) = repoItem.action else {
            Issue.record("Expected repo item to navigate")
            return
        }
        let worktreeItem = try #require(level.items.first { $0.id == "repo-wt-\(main.id.uuidString)" })
        #expect(worktreeItem.keywords.contains("client-alpha"))
        #expect(worktreeItem.keywords.contains("review-slice"))
    }

    @Test
    func test_repoLevelShowsOpenCommandsBeforeWorktrees() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/repo-level-actions"))
        let main = Worktree(
            repoId: repo.id,
            name: "main",
            path: URL(filePath: "/tmp/repo-level-actions"),
            isMainWorktree: true
        )
        let feature = Worktree(
            repoId: repo.id,
            name: "feature",
            path: URL(filePath: "/tmp/repo-level-actions-feature")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [main, feature])
        guard let storedRepo = store.repos.first else {
            Issue.record("Expected stored repo")
            return
        }

        let level = CommandBarDataSource.buildRepoLevel(repo: storedRepo, store: store)

        #expect(level.title == "repo-level-actions")
        #expect(level.scopeLabel == "Repo")
        #expect(level.items.map(\.title).prefix(2) == ["Copy Path", "Reveal in Finder"])
        #expect(level.items[0].group == "Open")
        #expect(level.items[1].group == "Open")
        #expect(level.items.contains { $0.title == "main" && $0.group == "Worktrees" })
        #expect(level.items.contains { $0.title == "feature" && $0.group == "Worktrees" })
    }

    @Test
    func test_worktreeLevelUsesSingleOpenGroupForPathAndPaneActions() {
        let presence = makeWorktreePresence(paneCount: 1)
        let worktree = Worktree(
            repoId: presence.repoId,
            name: presence.worktreeName,
            path: URL(filePath: "/tmp/repo/main"),
            isMainWorktree: presence.isMainWorktree
        )

        let level = CommandBarDataSource.buildWorktreeActionsLevel(
            worktree: worktree,
            presence: presence,
            canOpenInCurrentTab: true
        )

        let openTitles = level.items.filter { $0.group == "Open" }.map(\.title)
        #expect(
            openTitles == [
                "Copy Path",
                "Reveal in Finder",
                "New pane in new tab",
                "New pane in current tab",
            ])
        #expect(level.items.contains { $0.group == "Navigate to" && $0.title == "Terminal — main" })
    }

    @Test
    func test_everythingScope_repoItemsNavigateToRepoLevel() {
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
            launchDirectory: storedWorktree.path,
            title: "Terminal",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: storedWorktree.id, cwd: storedWorktree.path),
        )
        store.appendTab(Tab(paneId: pane.id))

        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        let repoItem = items.first { $0.id == "repo-\(repo.id.uuidString)" }
        #expect(repoItem != nil)
        #expect(repoItem?.worktreeOpenState == nil)
        #expect(repoItem?.subtitle == "● Tab 1 · 1 pane")
        #expect(repoItem?.group == "Repos")
        #expect(!items.contains { $0.id == "repo-wt-\(storedWorktree.id.uuidString)" })
        guard case .navigateRepo(let level) = repoItem?.action else {
            Issue.record("Expected everything-scope repo item to navigate to repo level")
            return
        }
        #expect(level.items.contains { $0.id == "repo-wt-\(storedWorktree.id.uuidString)" })
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
            launchDirectory: storedWorktree.path,
            title: "Terminal",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: storedWorktree.id, cwd: storedWorktree.path),
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
            launchDirectory: storedWorktree.path,
            title: "Terminal",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: storedWorktree.id, cwd: storedWorktree.path),
        )
        store.appendTab(Tab(paneId: pane.id))

        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        let tabItems = items.filter { $0.id.hasPrefix("tab-") }
        #expect(tabItems.count == 1)
    }

    @Test
    func test_everythingScope_usesRepoIdsForLocationRows() {
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
        let repoItem = items.first { $0.id == "repo-\(repo.id.uuidString)" }

        #expect(oldStyleItems.isEmpty)
        #expect(repoItem != nil)
        #expect(!items.contains { $0.id == "repo-wt-\(worktree.id.uuidString)" })
    }

    @Test
    func test_everythingScope_tabKeywordsIncludeArrangementNames() {
        let store = makeStore()
        let pane = store.createPane()
        var tab = Tab(paneId: pane.id)
        let namedArrangement = PaneArrangement(
            name: "Review",
            isDefault: false,
            layout: tab.layout
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
        let pane = store.createPane()
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
        guard let storedWorktree = store.repos.first?.worktrees.first else {
            Issue.record("Expected stored worktree")
            return
        }

        let items = CommandBarDataSource.items(
            scope: .repos, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        let item = items.first { $0.id == "repo-\(repo.id.uuidString)" }
        #expect(item != nil)
        #expect(item?.worktreeOpenState == nil)
        #expect(item?.hasChildren == true)
        guard case .navigateRepo(let level) = item?.action else {
            Issue.record("Expected repo item to navigate")
            return
        }
        let worktreeItem = level.items.first { $0.id == "repo-wt-\(storedWorktree.id.uuidString)" }
        #expect(worktreeItem?.subtitle == "main worktree")
        #expect(worktreeItem?.hasChildren == true)
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
            launchDirectory: storedWorktree.path,
            title: "Terminal",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: storedWorktree.id, cwd: storedWorktree.path),
        )
        store.appendTab(Tab(paneId: pane.id))

        let items = CommandBarDataSource.items(
            scope: .repos, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        let item = items.first { $0.id == "repo-\(repo.id.uuidString)" }
        #expect(item?.worktreeOpenState == nil)
        #expect(item?.subtitle?.contains("Tab 1") == true)
        #expect(item?.hasChildren == true)
        guard let item else {
            Issue.record("Expected repo item")
            return
        }
        guard case .navigateRepo(let level) = item.action else {
            Issue.record("Expected repo item to navigate")
            return
        }
        let worktreeItem = level.items.first { $0.id == "repo-wt-\(storedWorktree.id.uuidString)" }
        #expect(worktreeItem?.subtitle?.contains("Tab 1") == true)
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
            launchDirectory: storedWorktree.path,
            title: "A",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: storedWorktree.id, cwd: storedWorktree.path),
        )
        store.appendTab(Tab(paneId: paneA.id))
        let paneB = store.createPane(
            launchDirectory: storedWorktree.path,
            title: "B",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: storedWorktree.id, cwd: storedWorktree.path),
        )
        store.appendTab(Tab(paneId: paneB.id))

        let items = CommandBarDataSource.items(
            scope: .repos, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        let item = items.first { $0.id == "repo-\(repo.id.uuidString)" }
        #expect(item?.worktreeOpenState == nil)
        #expect(item?.subtitle?.contains("2 panes") == true)
        #expect(item?.hasChildren == true)
        guard let item else {
            Issue.record("Expected repo item")
            return
        }
        guard case .navigateRepo(let level) = item.action else {
            Issue.record("Expected repo item to navigate")
            return
        }
        let worktreeItem = level.items.first { $0.id == "repo-wt-\(storedWorktree.id.uuidString)" }
        #expect(worktreeItem?.subtitle?.contains("2 panes") == true)
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
            launchDirectory: storedWorktree.path,
            title: "T",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: storedWorktree.id, cwd: storedWorktree.path),
        )
        store.appendTab(Tab(paneId: pane.id))

        let items = CommandBarDataSource.items(
            scope: .repos, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let item = items.first { $0.id == "repo-\(repo.id.uuidString)" }

        #expect(item?.subtitle == "● Tab 1 · 1 pane")
    }
}
