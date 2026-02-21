import XCTest

@testable import AgentStudio

@MainActor
final class CommandBarDataSourceTests: XCTestCase {

    private var store: WorkspaceStore!
    private var dispatcher: CommandDispatcher!

    override func setUp() {
        super.setUp()
        store = WorkspaceStore()
        dispatcher = CommandDispatcher.shared
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    // MARK: - Everything Scope

    func test_everythingScope_includesCommands() {
        // Act
        let items = CommandBarDataSource.items(scope: .everything, store: store, dispatcher: dispatcher)

        // Assert — should include command items
        let commandItems = items.filter { $0.id.hasPrefix("cmd-") }
        XCTAssertGreaterThan(commandItems.count, 0)
    }

    func test_everythingScope_emptyStore_noTabOrPaneItems() {
        // Act — store has no views/tabs/sessions
        let items = CommandBarDataSource.items(scope: .everything, store: store, dispatcher: dispatcher)

        // Assert
        let tabItems = items.filter { $0.id.hasPrefix("tab-") }
        let paneItems = items.filter { $0.id.hasPrefix("pane-") }
        XCTAssertEqual(tabItems.count, 0)
        XCTAssertEqual(paneItems.count, 0)
    }

    // MARK: - Commands Scope

    func test_commandsScope_returnsOnlyCommands() {
        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)

        // Assert — all items should be commands
        XCTAssertTrue(items.allSatisfy { $0.id.hasPrefix("cmd-") })
        XCTAssertGreaterThan(items.count, 0)
    }

    func test_commandsScope_excludesHiddenCommands() {
        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)

        // Assert — selectTab1..9, quickFind, commandBar should be hidden
        let ids = items.map(\.id)
        XCTAssertFalse(ids.contains("cmd-selectTab1"))
        XCTAssertFalse(ids.contains("cmd-quickFind"))
        XCTAssertFalse(ids.contains("cmd-commandBar"))
    }

    func test_commandsScope_hasCorrectSubgroups() {
        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)
        let groups = Set(items.map(\.group))

        // Assert — should have named sub-groups
        XCTAssertTrue(groups.contains("Pane"))
        XCTAssertTrue(groups.contains("Focus"))
        XCTAssertTrue(groups.contains("Tab"))
        XCTAssertTrue(groups.contains("Repo"))
        XCTAssertTrue(groups.contains("Window"))
    }

    func test_commandsScope_commandsHaveLabelsAndIcons() {
        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)

        // Assert — commands should have titles, most have icons
        XCTAssertTrue(items.allSatisfy { !$0.title.isEmpty })
        let withIcons = items.filter { $0.icon != nil }
        XCTAssertGreaterThan(withIcons.count, items.count / 2)
    }

    func test_commandsScope_shortcutKeysPresent() {
        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)

        // Assert — some commands have keyboard shortcuts
        let withShortcuts = items.filter { $0.shortcutKeys != nil && !$0.shortcutKeys!.isEmpty }
        XCTAssertGreaterThan(withShortcuts.count, 0)
    }

    // MARK: - Panes Scope

    func test_panesScope_emptyStore_returnsEmpty() {
        // Act
        let items = CommandBarDataSource.items(scope: .panes, store: store, dispatcher: dispatcher)

        // Assert
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Grouping

    func test_grouped_sortsbyPriority() {
        // Arrange
        let items = [
            makeCommandBarItem(id: "a", group: "Worktrees", groupPriority: 4),
            makeCommandBarItem(id: "b", group: "Tabs", groupPriority: 1),
            makeCommandBarItem(id: "c", group: "Commands", groupPriority: 3),
        ]

        // Act
        let groups = CommandBarDataSource.grouped(items)

        // Assert
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups[0].name, "Tabs")
        XCTAssertEqual(groups[1].name, "Commands")
        XCTAssertEqual(groups[2].name, "Worktrees")
    }

    func test_grouped_groupsItemsByGroupName() {
        // Arrange
        let items = [
            makeCommandBarItem(id: "a", group: "Tab", groupPriority: 1),
            makeCommandBarItem(id: "b", group: "Tab", groupPriority: 1),
            makeCommandBarItem(id: "c", group: "Pane", groupPriority: 0),
        ]

        // Act
        let groups = CommandBarDataSource.grouped(items)

        // Assert
        XCTAssertEqual(groups.count, 2)
        let tabGroup = groups.first { $0.name == "Tab" }
        XCTAssertEqual(tabGroup?.items.count, 2)
    }

    func test_grouped_emptyItems_returnsEmpty() {
        // Act
        let groups = CommandBarDataSource.grouped([])

        // Assert
        XCTAssertTrue(groups.isEmpty)
    }

    // MARK: - Arrangement Commands

    func test_commandsScope_includesArrangementCommands() {
        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)

        // Assert
        let ids = items.map(\.id)
        XCTAssertTrue(ids.contains("cmd-switchArrangement"))
        XCTAssertTrue(ids.contains("cmd-saveArrangement"))
        XCTAssertTrue(ids.contains("cmd-deleteArrangement"))
        XCTAssertTrue(ids.contains("cmd-renameArrangement"))
    }

    func test_commandsScope_arrangementCommandsInTabGroup() {
        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)

        // Assert
        let arrangementItems = items.filter {
            $0.id == "cmd-switchArrangement" || $0.id == "cmd-saveArrangement" || $0.id == "cmd-deleteArrangement"
                || $0.id == "cmd-renameArrangement"
        }
        XCTAssertEqual(arrangementItems.count, 4, "All four arrangement commands should be present")
        XCTAssertTrue(arrangementItems.allSatisfy { $0.group == "Tab" })
    }

    func test_commandsScope_targetableArrangementCommandsHaveChildren() {
        // Arrange — need a tab with arrangements for drill-in to work
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

        XCTAssertTrue(switchItem?.hasChildren ?? false, "switchArrangement should have drill-in")
        XCTAssertTrue(deleteItem?.hasChildren ?? false, "deleteArrangement should have drill-in")
        XCTAssertTrue(renameItem?.hasChildren ?? false, "renameArrangement should have drill-in")
        XCTAssertFalse(saveItem?.hasChildren ?? true, "saveArrangement should NOT have drill-in")
    }

    // MARK: - Drawer Commands

    func test_commandsScope_includesDrawerCommands() {
        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)

        // Assert — all four drawer commands should appear
        let ids = items.map(\.id)
        XCTAssertTrue(ids.contains("cmd-addDrawerPane"), "addDrawerPane should be present")
        XCTAssertTrue(ids.contains("cmd-toggleDrawer"), "toggleDrawer should be present")
        XCTAssertTrue(ids.contains("cmd-navigateDrawerPane"), "navigateDrawerPane should be present")
        XCTAssertTrue(ids.contains("cmd-closeDrawerPane"), "closeDrawerPane should be present")
    }

    func test_commandsScope_drawerCommandsInPaneGroup() {
        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)

        // Assert — all drawer commands should be in the "Pane" group
        let drawerItems = items.filter {
            $0.id == "cmd-addDrawerPane" || $0.id == "cmd-toggleDrawer" || $0.id == "cmd-navigateDrawerPane"
                || $0.id == "cmd-closeDrawerPane"
        }
        XCTAssertEqual(drawerItems.count, 4, "All four drawer commands should be present")
        XCTAssertTrue(drawerItems.allSatisfy { $0.group == "Pane" }, "All drawer commands should be in the Pane group")
    }

    func test_commandsScope_navigateDrawerPaneIsTargetable() {
        // Arrange — need a pane with a drawer for drill-in to work
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        store.addDrawerPane(to: pane.id)

        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)

        // Assert — navigateDrawerPane should have drill-in (hasChildren: true)
        let navigateItem = items.first { $0.id == "cmd-navigateDrawerPane" }
        XCTAssertNotNil(navigateItem, "navigateDrawerPane command should exist")
        XCTAssertTrue(navigateItem?.hasChildren ?? false, "navigateDrawerPane should have drill-in")
    }

    func test_navigateDrawerPane_targetLevel_listsDrawerPanes() {
        // Arrange — create a pane with two drawer panes
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let drawer1 = store.addDrawerPane(to: pane.id)
        let drawer2 = store.addDrawerPane(to: pane.id)
        XCTAssertNotNil(drawer1, "First drawer pane should be created")
        XCTAssertNotNil(drawer2, "Second drawer pane should be created")

        // Act
        let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)
        let navigateItem = items.first { $0.id == "cmd-navigateDrawerPane" }
        XCTAssertNotNil(navigateItem, "navigateDrawerPane command should exist")

        // Assert — action should be .navigate with a level containing both drawer panes
        guard case .navigate(let level) = navigateItem?.action else {
            XCTFail("navigateDrawerPane action should be .navigate, got \(String(describing: navigateItem?.action))")
            return
        }

        XCTAssertEqual(level.items.count, 2, "Target level should list both drawer panes")
        XCTAssertEqual(level.id, "level-navigateDrawerPane", "Level ID should match command")

        let levelTitles = level.items.map(\.title)
        XCTAssertTrue(levelTitles.allSatisfy { $0 == "Drawer" }, "All drawer panes should have default title 'Drawer'")

        // Verify target IDs match the created drawer panes
        let levelIds = level.items.map(\.id)
        XCTAssertTrue(
            levelIds.contains("target-drawer-\(drawer1!.id.uuidString)"), "Level should target first drawer pane")
        XCTAssertTrue(
            levelIds.contains("target-drawer-\(drawer2!.id.uuidString)"), "Level should target second drawer pane")

        // Verify the active drawer pane has "Active" subtitle (last added becomes active)
        let activeItem = level.items.first { $0.id == "target-drawer-\(drawer2!.id.uuidString)" }
        XCTAssertEqual(activeItem?.subtitle, "Active", "Last added drawer pane should be marked as active")
    }
}
