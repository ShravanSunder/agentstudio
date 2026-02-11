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
}
