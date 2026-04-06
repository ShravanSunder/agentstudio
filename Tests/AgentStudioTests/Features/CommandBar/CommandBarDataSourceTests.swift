import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct CommandBarDataSourceTests {
    init() {
        installTestAtomScopeIfNeeded()
    }

    private let dispatcher = CommandDispatcher.shared

    private func makeStore() -> WorkspaceStore {
        WorkspaceStore()
    }

    private func makeRepoCache() -> RepoCacheAtom {
        RepoCacheAtom()
    }

    private func makeRichCommandStore() -> WorkspaceStore {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/command-bar-rich-state"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "feature-rich",
            path: URL(filePath: "/tmp/command-bar-rich-state/feature-rich")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])

        let paneA = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Primary"
        )
        let paneB = store.createPane(source: .floating(launchDirectory: nil, title: "Secondary"))
        var tab = Tab(paneId: paneA.id)
        let namedArrangement = PaneArrangement(
            name: "Review",
            isDefault: false,
            layout: tab.layout,
            visiblePaneIds: Set(tab.activePaneIds)
        )
        tab.arrangements.append(namedArrangement)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        store.insertPane(paneB.id, inTab: tab.id, at: paneA.id, direction: .horizontal, position: .after)
        _ = store.addDrawerPane(to: paneA.id)

        return store
    }

    // MARK: - Everything Scope

    @Test
    func test_everythingScope_includesCommands() {
        let store = makeStore()

        // Act
        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        // Assert — should include command items
        let commandItems = items.filter { $0.id.hasPrefix("cmd-") }
        #expect(!commandItems.isEmpty)
    }

    @Test
    func test_everythingScope_emptyStore_noTabOrPaneItems() {
        let store = makeStore()

        // Act — store has no views/tabs/sessions
        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        // Assert
        let tabItems = items.filter { $0.id.hasPrefix("tab-") }
        let paneItems = items.filter { $0.id.hasPrefix("pane-") }
        #expect(tabItems.isEmpty)
        #expect(paneItems.isEmpty)
    }

    // MARK: - Commands Scope

    @Test
    func test_commandsScope_returnsOnlyCommands() {
        let store = makeStore()

        // Act
        let items = CommandBarDataSource.items(
            scope: .commands, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        // Assert — all items should be commands
        #expect(items.allSatisfy { $0.id.hasPrefix("cmd-") })
        #expect(!items.isEmpty)
    }

    @Test
    func test_commandsScope_excludesHiddenCommands() {
        let store = makeStore()

        // Act
        let items = CommandBarDataSource.items(
            scope: .commands, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        // Assert — selectTab1..9, quickFind, commandBar should be hidden
        let ids = items.map(\.id)
        #expect(!ids.contains("cmd-selectTab1"))
        #expect(!ids.contains("cmd-quickFind"))
        #expect(!ids.contains("cmd-commandBar"))
    }

    @Test
    func test_commandsScope_hidesUnsupportedWindowCommands() {
        let store = makeStore()

        let items = CommandBarDataSource.items(
            scope: .commands, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let ids = Set(items.map(\.id))

        #expect(!ids.contains("cmd-newWindow"))
        #expect(!ids.contains("cmd-closeWindow"))
    }

    @Test
    func test_commandsScope_hasCorrectSubgroups() {
        let store = makeRichCommandStore()

        // Act
        let items = CommandBarDataSource.items(
            scope: .commands, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let groups = Set(items.map(\.group))

        // Assert — should have named sub-groups
        #expect(groups.contains("Pane"))
        #expect(groups.contains("Focus"))
        #expect(groups.contains("Tab"))
        #expect(groups.contains("Repo"))
        #expect(groups.contains("Window"))
        #expect(groups.contains("Webview"))
    }

    @Test
    func test_commandsScope_emptyWorkspaceHidesPaneAndTabSpecificCommands() {
        let store = makeStore()

        let items = CommandBarDataSource.items(
            scope: .commands, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let ids = Set(items.map(\.id))

        #expect(!ids.contains("cmd-closePane"))
        #expect(!ids.contains("cmd-addDrawerPane"))
        #expect(!ids.contains("cmd-closeTab"))
        #expect(!ids.contains("cmd-switchArrangement"))
        #expect(!ids.contains("cmd-deleteArrangement"))
        #expect(!ids.contains("cmd-renameArrangement"))
        #expect(!ids.contains("cmd-saveArrangement"))
        #expect(ids.contains("cmd-newTab"))
        #expect(ids.contains("cmd-addRepo"))
    }

    @Test
    func test_commandsScope_commandsHaveLabelsAndIcons() {
        let store = makeStore()

        // Act
        let items = CommandBarDataSource.items(
            scope: .commands, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        // Assert — commands should have titles, most have icons
        #expect(items.allSatisfy { !$0.title.isEmpty })
        let withIcons = items.filter { $0.icon != nil }
        #expect(withIcons.count > items.count / 2)
    }

    @Test
    func test_commandsScope_shortcutKeysPresent() {
        let store = makeStore()

        // Act
        let items = CommandBarDataSource.items(
            scope: .commands, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        // Assert — some commands have keyboard shortcuts
        let withShortcuts = items.filter { $0.shortcutKeys != nil && !$0.shortcutKeys!.isEmpty }
        #expect(!withShortcuts.isEmpty)
    }

    // MARK: - Panes Scope

    @Test
    func test_panesScope_emptyStore_returnsEmpty() {
        let store = makeStore()

        // Act
        let items = CommandBarDataSource.items(
            scope: .panes, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        // Assert
        #expect(items.isEmpty)
    }

    @Test
    func test_panesScope_usesCommandBarTabTitleAndSubtitle() {
        let store = makeStore()
        let repoCache = makeRepoCache()
        let repo = store.addRepo(at: URL(filePath: "/tmp/agent-studio"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "feature-name",
            path: URL(filePath: "/tmp/agent-studio/feature-name")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktree.id, repoId: repo.id, branch: "feature/pane-labels")
        )
        let pane = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Shell title",
            facets: PaneContextFacets(
                repoId: repo.id,
                repoName: repo.name,
                worktreeId: worktree.id,
                worktreeName: worktree.name,
                cwd: worktree.path
            )
        )
        store.appendTab(Tab(paneId: pane.id))

        let items = CommandBarDataSource.items(
            scope: .panes,
            store: store,
            repoCache: repoCache,
            dispatcher: dispatcher
        )

        let tabItem = items.first { $0.id == "tab-\(store.tabs[0].id.uuidString)" }
        let paneItem = items.first { $0.id == "pane-\(pane.id.uuidString)" }

        #expect(tabItem?.title == "agent-studio")
        #expect(tabItem?.subtitle == "Active Tab")
        #expect(paneItem?.title == "Terminal — feature/pane-labels")
    }

    @Test
    func test_everythingScope_tabSubtitleIncludesPaneCount() {
        let store = makeStore()
        let paneA = store.createPane(source: .floating(launchDirectory: nil, title: "Pane A"))
        let paneB = store.createPane(source: .floating(launchDirectory: nil, title: "Pane B"))
        let paneC = store.createPane(source: .floating(launchDirectory: nil, title: "Pane C"))

        let tab = Tab(paneId: paneA.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        store.insertPane(paneB.id, inTab: tab.id, at: paneA.id, direction: .horizontal, position: .after)
        store.insertPane(paneC.id, inTab: tab.id, at: paneB.id, direction: .horizontal, position: .after)

        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let tabItem = items.first { $0.id == "tab-\(tab.id.uuidString)" }

        #expect(tabItem?.subtitle == "Active · Tab 1 · 3 panes")
    }

    @Test
    func test_everythingScope_webviewPaneUsesHostInTitle() throws {
        let store = makeStore()
        let pane = store.createPane(
            content: .webview(
                WebviewState(url: try #require(URL(string: "https://localhost:3000")), title: "", showNavigation: true)
            ),
            metadata: PaneMetadata(
                source: .init(.floating(launchDirectory: nil, title: nil)),
                title: "Webview"
            )
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let paneItem = items.first { $0.id == "pane-\(pane.id.uuidString)" }

        #expect(paneItem?.title == "Webview — localhost")
    }

    @Test
    func test_everythingScope_webviewFileURLUsesLastPathComponentInTitle() {
        let store = makeStore()
        let pane = store.createPane(
            content: .webview(
                WebviewState(
                    url: URL(fileURLWithPath: "/tmp/previews/index.html"),
                    title: "",
                    showNavigation: true
                )
            ),
            metadata: PaneMetadata(
                source: .init(.floating(launchDirectory: nil, title: nil)),
                title: "Webview"
            )
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let paneItem = items.first { $0.id == "pane-\(pane.id.uuidString)" }

        #expect(paneItem?.title == "Webview — index.html")
    }

    @Test
    func test_everythingScope_tabItem_dispatchesTargetedSelectTabCommand() {
        let store = makeStore()
        let pane = store.createPane(source: .floating(launchDirectory: nil, title: "Pane A"))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let tabItem = items.first { $0.id == "tab-\(tab.id.uuidString)" }

        guard case .dispatchTargeted(let command, let target, let targetType) = tabItem?.action else {
            Issue.record("Expected tab item to dispatch a targeted selection command")
            return
        }

        #expect(command == .selectTab)
        #expect(target == tab.id)
        #expect(targetType == .tab)
    }

    @Test
    func test_everythingScope_paneItem_dispatchesTargetedFocusPaneCommand() {
        let store = makeStore()
        let pane = store.createPane(source: .floating(launchDirectory: nil, title: "Pane A"))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let paneItem = items.first { $0.id == "pane-\(pane.id.uuidString)" }

        guard case .dispatchTargeted(let command, let target, let targetType) = paneItem?.action else {
            Issue.record("Expected pane item to dispatch a targeted focus command")
            return
        }

        #expect(command == .focusPane)
        #expect(target == pane.id)
        #expect(targetType == .floatingTerminal)
    }

    @Test
    func test_everythingScope_emptyTabUsesEmptyTabTitle() {
        let store = makeStore()
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(),
            visiblePaneIds: []
        )
        let tab = Tab(
            name: "Empty",
            panes: [],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: nil
        )
        store.appendTab(tab)

        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let tabItem = items.first { $0.id == "tab-\(tab.id.uuidString)" }

        #expect(tabItem?.title == "Empty Tab")
    }

    @Test
    func test_everythingScope_tabTitleFallsBackToPrimaryLabelWhenRepoNameMissing() {
        let store = makeStore()
        let pane = store.createPane(
            source: .floating(launchDirectory: nil, title: nil),
            title: "Scratch Pad"
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let tabItem = items.first { $0.id == "tab-\(tab.id.uuidString)" }

        #expect(tabItem?.title == "Scratch Pad")
    }

    @Test
    func test_everythingScope_terminalPaneFallsBackToPrimaryLabelWithoutBranchOrCwd() {
        let store = makeStore()
        let pane = store.createPane(
            source: .floating(launchDirectory: nil, title: nil),
            title: "Scratch Pad"
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let paneItem = items.first { $0.id == "pane-\(pane.id.uuidString)" }

        #expect(paneItem?.title == "Scratch Pad")
    }

    @Test
    func test_everythingScope_terminalPaneUsesCwdFolderWithoutBranch() {
        let store = makeStore()
        let pane = store.createPane(
            source: .floating(
                launchDirectory: URL(fileURLWithPath: "/tmp/workspace-demo"),
                title: "Shell"
            ),
            title: "Shell",
            facets: PaneContextFacets(cwd: URL(fileURLWithPath: "/tmp/workspace-demo"))
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let paneItem = items.first { $0.id == "pane-\(pane.id.uuidString)" }

        #expect(paneItem?.title == "Terminal — workspace-demo")
    }

    @Test
    func test_everythingScope_bridgePaneUsesBridgeFallbackLabel() {
        let store = makeStore()
        let pane = store.createPane(
            content: .bridgePanel(BridgePaneState(panelKind: .diffViewer, source: nil)),
            metadata: PaneMetadata(
                source: .init(.floating(launchDirectory: nil, title: nil)),
                title: "Bridge"
            )
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let paneItem = items.first { $0.id == "pane-\(pane.id.uuidString)" }

        #expect(paneItem?.title == "Bridge — Panel")
    }

    @Test
    func test_everythingScope_codeViewerPaneUsesCodeFallbackLabel() {
        let store = makeStore()
        let pane = store.createPane(
            content: .codeViewer(
                CodeViewerState(filePath: URL(fileURLWithPath: "/tmp/example.swift"), scrollToLine: 42)
            ),
            metadata: PaneMetadata(
                source: .init(.floating(launchDirectory: nil, title: nil)),
                title: "Code"
            )
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let paneItem = items.first { $0.id == "pane-\(pane.id.uuidString)" }

        #expect(paneItem?.title == "Code — Viewer")
    }

    @Test
    func test_everythingScope_unsupportedPaneUsesCwdFolderWithoutTerminalPrefix() {
        let store = makeStore()
        let pane = store.createPane(
            content: .unsupported(UnsupportedContent(type: "future-pane", version: 3, rawState: nil)),
            metadata: PaneMetadata(
                source: .init(
                    .floating(
                        launchDirectory: URL(fileURLWithPath: "/tmp/unsupported-pane"),
                        title: nil
                    )
                ),
                title: "Unsupported",
                facets: PaneContextFacets(cwd: URL(fileURLWithPath: "/tmp/unsupported-pane"))
            )
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        let items = CommandBarDataSource.items(
            scope: .everything, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let paneItem = items.first { $0.id == "pane-\(pane.id.uuidString)" }

        #expect(paneItem?.title == "unsupported-pane")
    }

    // MARK: - Grouping

    @Test
    func test_grouped_sortsbyPriority() {
        let items = [
            makeCommandBarItem(id: "a", group: "Worktrees", groupPriority: 4),
            makeCommandBarItem(id: "b", group: "Tabs", groupPriority: 1),
            makeCommandBarItem(id: "c", group: "Commands", groupPriority: 3),
        ]

        // Act
        let groups = CommandBarDataSource.grouped(items)

        // Assert
        #expect(groups.count == 3)
        #expect(groups[0].name == "Tabs")
        #expect(groups[1].name == "Commands")
        #expect(groups[2].name == "Worktrees")
    }

    @Test
    func test_grouped_groupsItemsByGroupName() {
        let items = [
            makeCommandBarItem(id: "a", group: "Tab", groupPriority: 1),
            makeCommandBarItem(id: "b", group: "Tab", groupPriority: 1),
            makeCommandBarItem(id: "c", group: "Pane", groupPriority: 0),
        ]

        // Act
        let groups = CommandBarDataSource.grouped(items)

        // Assert
        #expect(groups.count == 2)
        let tabGroup = groups.first { $0.name == "Tab" }
        #expect(tabGroup?.items.count == 2)
    }

    @Test
    func test_grouped_emptyItems_returnsEmpty() {
        // Act
        let groups = CommandBarDataSource.grouped([])

        // Assert
        #expect(groups.isEmpty)
    }

    // MARK: - Arrangement Commands

    @Test
    func test_commandsScope_includesArrangementCommands() {
        let store = makeRichCommandStore()

        // Act
        let items = CommandBarDataSource.items(
            scope: .commands, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        // Assert
        let ids = items.map(\.id)
        #expect(ids.contains("cmd-switchArrangement"))
        #expect(ids.contains("cmd-saveArrangement"))
        #expect(ids.contains("cmd-deleteArrangement"))
        #expect(ids.contains("cmd-renameArrangement"))
    }

    @Test
    func test_commandsScope_arrangementCommandsInTabGroup() {
        let store = makeRichCommandStore()

        // Act
        let items = CommandBarDataSource.items(
            scope: .commands, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        // Assert
        let arrangementItems = items.filter {
            $0.id == "cmd-switchArrangement" || $0.id == "cmd-saveArrangement" || $0.id == "cmd-deleteArrangement"
                || $0.id == "cmd-renameArrangement"
        }
        #expect(arrangementItems.count == 4)
        #expect(arrangementItems.allSatisfy { $0.group == "Tab" })
    }

    @Test
    func test_commandsScope_targetableArrangementCommandsHaveChildren() {
        // Arrange — need a tab with arrangements for drill-in to work
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

        // Act
        let items = CommandBarDataSource.items(
            scope: .commands, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        // Assert — targetable arrangement commands should show drill-in
        let switchItem = items.first { $0.id == "cmd-switchArrangement" }
        let deleteItem = items.first { $0.id == "cmd-deleteArrangement" }
        let renameItem = items.first { $0.id == "cmd-renameArrangement" }
        let saveItem = items.first { $0.id == "cmd-saveArrangement" }

        #expect((switchItem?.hasChildren ?? false) == true)
        #expect((deleteItem?.hasChildren ?? false) == true)
        #expect((renameItem?.hasChildren ?? false) == true)
        #expect((saveItem?.hasChildren ?? true) == false)
    }

    @Test
    func test_commandsScope_newTerminalInTabHasDrillIn() {
        let store = makeStore()
        let pane = store.createPane(source: .floating(launchDirectory: nil, title: "Pane A"))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let items = CommandBarDataSource.items(
            scope: .commands, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let newTerminalInTab = items.first { $0.id == "cmd-newTerminalInTab" }

        #expect(newTerminalInTab != nil)
        #expect((newTerminalInTab?.hasChildren ?? false) == true)
    }

    @Test
    func test_commandsScope_removeRepoHasDrillIn() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/remove-repo-command"))
        store.reconcileDiscoveredWorktrees(
            repo.id,
            worktrees: [
                Worktree(
                    repoId: repo.id,
                    name: "main",
                    path: URL(filePath: "/tmp/remove-repo-command"),
                    isMainWorktree: true
                )
            ]
        )

        let items = CommandBarDataSource.items(
            scope: .commands, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let removeRepo = items.first { $0.id == "cmd-removeRepo" }

        #expect(removeRepo != nil)
        #expect((removeRepo?.hasChildren ?? false) == true)
    }

    // MARK: - Move Pane Command

    @Test
    func test_commandsScope_movePaneToTab_hasDrillIn() {
        let store = makeStore()

        let paneA = store.createPane(source: .floating(launchDirectory: nil, title: "Pane A"))
        let paneB = store.createPane(source: .floating(launchDirectory: nil, title: "Pane B"))
        let tabA = Tab(paneId: paneA.id)
        let tabB = Tab(paneId: paneB.id)
        store.appendTab(tabA)
        store.appendTab(tabB)
        store.setActiveTab(tabA.id)

        let items = CommandBarDataSource.items(
            scope: .commands, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let moveItem = items.first { $0.id == "cmd-movePaneToTab" }

        #expect(moveItem != nil)
        #expect(moveItem?.group == "Pane")
        #expect((moveItem?.hasChildren ?? false) == true)
    }

    @Test
    func test_movePaneToTab_drillIn_postsMoveEvent() async {
        let store = makeStore()

        let paneA = store.createPane(source: .floating(launchDirectory: nil, title: "Pane A"))
        let paneB = store.createPane(source: .floating(launchDirectory: nil, title: "Pane B"))
        let tabA = Tab(paneId: paneA.id)
        let tabB = Tab(paneId: paneB.id)
        store.appendTab(tabA)
        store.appendTab(tabB)
        store.setActiveTab(tabA.id)

        let items = CommandBarDataSource.items(
            scope: .commands, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let moveItem = items.first { $0.id == "cmd-movePaneToTab" }
        guard case .navigate(let sourceLevel) = moveItem?.action else {
            Issue.record("Expected movePaneToTab command to navigate to source pane level")
            return
        }

        let sourceItem = sourceLevel.items.first { $0.id == "target-move-source-pane-\(paneA.id.uuidString)" }
        guard case .navigate(let destinationLevel) = sourceItem?.action else {
            Issue.record("Expected source pane row to navigate to destination tab level")
            return
        }
        let destinationItem = destinationLevel.items.first {
            $0.id == "target-move-dest-tab-\(paneA.id.uuidString)-\(tabB.id.uuidString)"
        }
        guard case .custom(let action) = destinationItem?.action else {
            Issue.record("Expected destination tab row to dispatch custom move action")
            return
        }
        action()
    }

    // MARK: - Repos Scope

    @Test
    func test_reposScope_emptyStore_returnsEmpty() {
        let store = makeStore()

        // Act
        let items = CommandBarDataSource.items(
            scope: .repos, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        // Assert
        #expect(items.isEmpty)
    }

    @Test
    func test_reposScope_usesFlatGroupForSingleWorktreeRepos() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/test-repo"))
        store.reconcileDiscoveredWorktrees(
            repo.id,
            worktrees: [
                Worktree(
                    repoId: repo.id,
                    name: "main",
                    path: URL(filePath: "/tmp/test-repo"),
                    isMainWorktree: true
                )
            ])

        // Act
        let items = CommandBarDataSource.items(
            scope: .repos, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        // Assert
        #expect(items.count == 1)
        #expect(items.allSatisfy { $0.id.hasPrefix("repo-wt-") })
        #expect(items.allSatisfy { $0.group == "Repos" })

        // Main worktree should rely on icon/subtitle rather than title decoration
        let mainItem = items.first { $0.title.contains("main") }
        #expect(mainItem?.title == "main")
        #expect(mainItem?.icon == "star.fill")
        #expect(mainItem?.subtitle == "main worktree")

    }

    @Test
    func test_reposScope_usesPerRepoGroupForMultiWorktreeRepos() {
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/multi-worktree-repo"))
        store.reconcileDiscoveredWorktrees(
            repo.id,
            worktrees: [
                Worktree(
                    repoId: repo.id,
                    name: "main",
                    path: URL(filePath: "/tmp/multi-worktree-repo"),
                    isMainWorktree: true
                ),
                Worktree(
                    repoId: repo.id,
                    name: "feature",
                    path: URL(filePath: "/tmp/multi-worktree-repo-feature")
                ),
            ]
        )

        let items = CommandBarDataSource.items(
            scope: .repos, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let groups = CommandBarDataSource.grouped(items)

        #expect(groups.count == 1)
        #expect(groups.first?.name == "\(repo.name) (worktrees)")
    }

    // MARK: - Drawer Commands

    @Test
    func test_commandsScope_includesDrawerCommands() {
        let store = makeRichCommandStore()

        // Act
        let items = CommandBarDataSource.items(
            scope: .commands, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        // Assert — all four drawer commands should appear once the active pane has drawer state
        let ids = items.map(\.id)
        #expect(ids.contains("cmd-addDrawerPane"))
        #expect(ids.contains("cmd-toggleDrawer"))
        #expect(ids.contains("cmd-navigateDrawerPane"))
        #expect(ids.contains("cmd-closeDrawerPane"))
    }

    @Test
    func test_commandsScope_drawerCommandsInPaneGroup() {
        let store = makeRichCommandStore()

        // Act
        let items = CommandBarDataSource.items(
            scope: .commands, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        // Assert — all drawer commands should be in the "Pane" group
        let drawerItems = items.filter {
            $0.id == "cmd-addDrawerPane" || $0.id == "cmd-toggleDrawer" || $0.id == "cmd-navigateDrawerPane"
                || $0.id == "cmd-closeDrawerPane"
        }
        #expect(drawerItems.count == 4)
        #expect(drawerItems.allSatisfy { $0.group == "Pane" })
    }

    @Test
    func test_commandsScope_navigateDrawerPaneIsTargetable() {
        let store = makeStore()
        let pane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        store.addDrawerPane(to: pane.id)

        // Act
        let items = CommandBarDataSource.items(
            scope: .commands, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)

        // Assert — navigateDrawerPane should have drill-in (hasChildren: true)
        let navigateItem = items.first { $0.id == "cmd-navigateDrawerPane" }
        #expect(navigateItem != nil)
        #expect((navigateItem?.hasChildren ?? false) == true)
    }

    @Test
    func test_navigateDrawerPane_targetLevel_listsDrawerPanes() {
        // Arrange — create a pane with two drawer panes
        let store = makeStore()
        let pane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let drawer1 = store.addDrawerPane(to: pane.id)
        let drawer2 = store.addDrawerPane(to: pane.id)
        #expect(drawer1 != nil)
        #expect(drawer2 != nil)

        // Act
        let items = CommandBarDataSource.items(
            scope: .commands, store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
        let navigateItem = items.first { $0.id == "cmd-navigateDrawerPane" }
        #expect(navigateItem != nil)

        // Assert — action should be .navigate with a level containing both drawer panes
        guard case .navigate(let level) = navigateItem?.action else {
            Issue.record(
                "navigateDrawerPane action should be .navigate, got \(String(describing: navigateItem?.action))")
            return
        }

        #expect(level.items.count == 2)
        #expect(level.id == "level-navigateDrawerPane")

        let levelTitles = level.items.map(\.title)
        #expect(levelTitles.allSatisfy { $0 == "Drawer" })

        // Verify target IDs match the created drawer panes
        let levelIds = level.items.map(\.id)
        #expect(
            levelIds.contains("target-drawer-\(drawer1!.id.uuidString)")
        )
        #expect(
            levelIds.contains("target-drawer-\(drawer2!.id.uuidString)")
        )

        // Verify the active drawer pane has "Active" subtitle (last added becomes active)
        let activeItem = level.items.first { $0.id == "target-drawer-\(drawer2!.id.uuidString)" }
        #expect(activeItem?.subtitle == "Active")
    }
}
