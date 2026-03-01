import Foundation
import Testing

@testable import AgentStudio

private final class AppEventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var event: AppEvent?

    func set(_ value: AppEvent) {
        lock.lock()
        event = value
        lock.unlock()
    }

    func get() -> AppEvent? {
        lock.lock()
        defer { lock.unlock() }
        return event
    }
}

@MainActor
@Suite(.serialized)
struct CommandBarDataSourceTests {
    private let dispatcher = CommandDispatcher.shared

    private func makeStore() -> WorkspaceStore {
        WorkspaceStore()
    }

    // MARK: - Everything Scope

    @Test
    func test_everythingScope_includesCommands() {
        let store = makeStore()

        // Act
        let items = CommandBarDataSource.items(scope: .everything, store: store, dispatcher: dispatcher)

        // Assert — should include command items
        let commandItems = items.filter { $0.id.hasPrefix("cmd-") }
        #expect(!commandItems.isEmpty)
    }

    @Test
    func test_everythingScope_emptyStore_noTabOrPaneItems() {
        let store = makeStore()

        // Act — store has no views/tabs/sessions
        let items = CommandBarDataSource.items(scope: .everything, store: store, dispatcher: dispatcher)

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
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)

        // Assert — all items should be commands
        #expect(items.allSatisfy { $0.id.hasPrefix("cmd-") })
        #expect(!items.isEmpty)
    }

    @Test
    func test_commandsScope_excludesHiddenCommands() {
        let store = makeStore()

        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)

        // Assert — selectTab1..9, quickFind, commandBar should be hidden
        let ids = items.map(\.id)
        #expect(!ids.contains("cmd-selectTab1"))
        #expect(!ids.contains("cmd-quickFind"))
        #expect(!ids.contains("cmd-commandBar"))
    }

    @Test
    func test_commandsScope_hasCorrectSubgroups() {
        let store = makeStore()

        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)
        let groups = Set(items.map(\.group))

        // Assert — should have named sub-groups
        #expect(groups.contains("Pane"))
        #expect(groups.contains("Focus"))
        #expect(groups.contains("Tab"))
        #expect(groups.contains("Repo"))
        #expect(groups.contains("Window"))
    }

    @Test
    func test_commandsScope_commandsHaveLabelsAndIcons() {
        let store = makeStore()

        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)

        // Assert — commands should have titles, most have icons
        #expect(items.allSatisfy { !$0.title.isEmpty })
        let withIcons = items.filter { $0.icon != nil }
        #expect(withIcons.count > items.count / 2)
    }

    @Test
    func test_commandsScope_shortcutKeysPresent() {
        let store = makeStore()

        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)

        // Assert — some commands have keyboard shortcuts
        let withShortcuts = items.filter { $0.shortcutKeys != nil && !$0.shortcutKeys!.isEmpty }
        #expect(!withShortcuts.isEmpty)
    }

    // MARK: - Panes Scope

    @Test
    func test_panesScope_emptyStore_returnsEmpty() {
        let store = makeStore()

        // Act
        let items = CommandBarDataSource.items(scope: .panes, store: store, dispatcher: dispatcher)

        // Assert
        #expect(items.isEmpty)
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
        let store = makeStore()

        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)

        // Assert
        let ids = items.map(\.id)
        #expect(ids.contains("cmd-switchArrangement"))
        #expect(ids.contains("cmd-saveArrangement"))
        #expect(ids.contains("cmd-deleteArrangement"))
        #expect(ids.contains("cmd-renameArrangement"))
    }

    @Test
    func test_commandsScope_arrangementCommandsInTabGroup() {
        let store = makeStore()

        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)

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
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)

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

    // MARK: - Move Pane Command

    @Test
    func test_commandsScope_movePaneToTab_hasDrillIn() {
        let store = makeStore()

        let paneA = store.createPane(source: .floating(workingDirectory: nil, title: "Pane A"))
        let paneB = store.createPane(source: .floating(workingDirectory: nil, title: "Pane B"))
        let tabA = Tab(paneId: paneA.id)
        let tabB = Tab(paneId: paneB.id)
        store.appendTab(tabA)
        store.appendTab(tabB)
        store.setActiveTab(tabA.id)

        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)
        let moveItem = items.first { $0.id == "cmd-movePaneToTab" }

        #expect(moveItem != nil)
        #expect(moveItem?.group == "Pane")
        #expect((moveItem?.hasChildren ?? false) == true)
    }

    @Test
    func test_movePaneToTab_drillIn_postsMoveEvent() async {
        let store = makeStore()

        let paneA = store.createPane(source: .floating(workingDirectory: nil, title: "Pane A"))
        let paneB = store.createPane(source: .floating(workingDirectory: nil, title: "Pane B"))
        let tabA = Tab(paneId: paneA.id)
        let tabB = Tab(paneId: paneB.id)
        store.appendTab(tabA)
        store.appendTab(tabB)
        store.setActiveTab(tabA.id)

        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)
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

        let eventBox = AppEventBox()
        let captureTask = Task {
            let stream = await AppEventBus.shared.subscribe()
            for await event in stream {
                guard case .movePaneToTabRequested = event else { continue }
                eventBox.set(event)
                break
            }
        }
        defer { captureTask.cancel() }
        try? await Task.sleep(for: .milliseconds(10))

        action()
        try? await Task.sleep(for: .milliseconds(20))

        guard let postedEvent = eventBox.get() else {
            Issue.record("Expected movePaneToTabRequested event to be posted")
            return
        }
        guard
            case .movePaneToTabRequested(
                let paneId,
                let sourceTabId,
                let targetTabId
            ) = postedEvent
        else {
            Issue.record("Expected movePaneToTabRequested event payload")
            return
        }

        #expect(paneId == paneA.id)
        #expect(sourceTabId == tabA.id)
        #expect(targetTabId == tabB.id)
    }

    // MARK: - Repos Scope

    @Test
    func test_reposScope_emptyStore_returnsEmpty() {
        let store = makeStore()

        // Act
        let items = CommandBarDataSource.items(scope: .repos, store: store, dispatcher: dispatcher)

        // Assert
        #expect(items.isEmpty)
    }

    @Test
    func test_reposScope_returnsWorktreesGroupedByRepo() {
        // Arrange
        let store = makeStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/test-repo"))
        store.reconcileDiscoveredWorktrees(
            repo.id,
            worktrees: [
                Worktree(
                    name: "main",
                    path: URL(filePath: "/tmp/test-repo"),
                    branch: "main",
                    isMainWorktree: true
                ),
                Worktree(
                    name: "feat-branch",
                    path: URL(filePath: "/tmp/test-repo-feat"),
                    branch: "feat/branch",
                    isMainWorktree: false
                ),
            ])

        // Act
        let items = CommandBarDataSource.items(scope: .repos, store: store, dispatcher: dispatcher)

        // Assert
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.id.hasPrefix("repo-wt-") })
        #expect(items.allSatisfy { $0.group == repo.name })

        // Main worktree should have star prefix and star icon
        let mainItem = items.first { $0.title.contains("main") }
        #expect(mainItem?.title.hasPrefix("★") == true)
        #expect(mainItem?.icon == "star.fill")

        // Feature branch should have branch icon
        let featItem = items.first { $0.title.contains("feat-branch") }
        #expect(featItem?.icon == "arrow.triangle.branch")
    }

    // MARK: - Drawer Commands

    @Test
    func test_commandsScope_includesDrawerCommands() {
        let store = makeStore()

        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)

        // Assert — all four drawer commands should appear
        let ids = items.map(\.id)
        #expect(ids.contains("cmd-addDrawerPane"))
        #expect(ids.contains("cmd-toggleDrawer"))
        #expect(ids.contains("cmd-navigateDrawerPane"))
        #expect(ids.contains("cmd-closeDrawerPane"))
    }

    @Test
    func test_commandsScope_drawerCommandsInPaneGroup() {
        let store = makeStore()

        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)

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
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        store.addDrawerPane(to: pane.id)

        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)

        // Assert — navigateDrawerPane should have drill-in (hasChildren: true)
        let navigateItem = items.first { $0.id == "cmd-navigateDrawerPane" }
        #expect(navigateItem != nil)
        #expect((navigateItem?.hasChildren ?? false) == true)
    }

    @Test
    func test_navigateDrawerPane_targetLevel_listsDrawerPanes() {
        // Arrange — create a pane with two drawer panes
        let store = makeStore()
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let drawer1 = store.addDrawerPane(to: pane.id)
        let drawer2 = store.addDrawerPane(to: pane.id)
        #expect(drawer1 != nil)
        #expect(drawer2 != nil)

        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)
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
