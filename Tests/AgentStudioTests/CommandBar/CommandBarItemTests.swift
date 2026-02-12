import XCTest
@testable import AgentStudio

final class CommandBarItemTests: XCTestCase {

    // MARK: - ShortcutKey from KeyBinding

    func test_shortcutKey_fromKeyBinding_commandW() {
        // Arrange
        let binding = KeyBinding(key: "w", modifiers: [.command])

        // Act
        let keys = ShortcutKey.from(keyBinding: binding)

        // Assert
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys[0].symbol, "⌘")
        XCTAssertEqual(keys[1].symbol, "W")
    }

    func test_shortcutKey_fromKeyBinding_commandShiftO() {
        // Arrange
        let binding = KeyBinding(key: "O", modifiers: [.command, .shift])

        // Act
        let keys = ShortcutKey.from(keyBinding: binding)

        // Assert
        XCTAssertEqual(keys.count, 3)
        XCTAssertEqual(keys[0].symbol, "⌘")
        XCTAssertEqual(keys[1].symbol, "⇧")
        XCTAssertEqual(keys[2].symbol, "O")
    }

    func test_shortcutKey_fromKeyBinding_allModifiers() {
        // Arrange
        let binding = KeyBinding(key: "k", modifiers: [.command, .shift, .option, .control])

        // Act
        let keys = ShortcutKey.from(keyBinding: binding)

        // Assert — order: command, shift, option, control, then key
        XCTAssertEqual(keys.count, 5)
        XCTAssertEqual(keys[0].symbol, "⌘")
        XCTAssertEqual(keys[1].symbol, "⇧")
        XCTAssertEqual(keys[2].symbol, "⌥")
        XCTAssertEqual(keys[3].symbol, "⌃")
        XCTAssertEqual(keys[4].symbol, "K")
    }

    func test_shortcutKey_fromKeyBinding_noModifiers() {
        // Arrange
        let binding = KeyBinding(key: "p", modifiers: [])

        // Act
        let keys = ShortcutKey.from(keyBinding: binding)

        // Assert
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].symbol, "P")
    }

    func test_shortcutKey_hashable_sameSymbolNotEqual() {
        // Arrange — two ShortcutKeys with same symbol get different UUIDs
        let key1 = ShortcutKey(symbol: "⌘")
        let key2 = ShortcutKey(symbol: "⌘")

        // Assert — they are not equal because id (UUID) differs
        XCTAssertNotEqual(key1, key2)
    }

    // MARK: - CommandBarItem Init

    func test_item_init_defaults() {
        // Arrange & Act
        let item = makeCommandBarItem()

        // Assert
        XCTAssertEqual(item.id, "test-item")
        XCTAssertEqual(item.title, "Test Item")
        XCTAssertNil(item.subtitle)
        XCTAssertEqual(item.icon, "terminal")
        XCTAssertNil(item.iconColor)
        XCTAssertNil(item.shortcutKeys)
        XCTAssertEqual(item.group, "Commands")
        XCTAssertEqual(item.groupPriority, 3)
        XCTAssertTrue(item.keywords.isEmpty)
        XCTAssertFalse(item.hasChildren)
    }

    func test_item_init_allProperties() {
        // Arrange
        let keys = [ShortcutKey(symbol: "⌘"), ShortcutKey(symbol: "W")]

        // Act
        let item = CommandBarItem(
            id: "close-tab",
            title: "Close Tab",
            subtitle: "Tab 1",
            icon: "xmark",
            iconColor: .red,
            shortcutKeys: keys,
            group: "Tab",
            groupPriority: 1,
            keywords: ["close", "remove"],
            hasChildren: true,
            action: .dispatch(.closeTab)
        )

        // Assert
        XCTAssertEqual(item.id, "close-tab")
        XCTAssertEqual(item.title, "Close Tab")
        XCTAssertEqual(item.subtitle, "Tab 1")
        XCTAssertEqual(item.icon, "xmark")
        XCTAssertEqual(item.iconColor, .red)
        XCTAssertEqual(item.shortcutKeys?.count, 2)
        XCTAssertEqual(item.group, "Tab")
        XCTAssertEqual(item.groupPriority, 1)
        XCTAssertEqual(item.keywords, ["close", "remove"])
        XCTAssertTrue(item.hasChildren)
    }

    // MARK: - CommandBarLevel Init

    func test_level_init_withParentLabel() {
        // Arrange & Act
        let level = makeCommandBarLevel(
            id: "tab-close",
            title: "Close Tab",
            parentLabel: "Tab"
        )

        // Assert
        XCTAssertEqual(level.id, "tab-close")
        XCTAssertEqual(level.title, "Close Tab")
        XCTAssertEqual(level.parentLabel, "Tab")
        XCTAssertTrue(level.items.isEmpty)
    }

    func test_level_init_withoutParentLabel() {
        // Arrange & Act
        let level = CommandBarLevel(id: "root", title: "Root", items: [])

        // Assert
        XCTAssertNil(level.parentLabel)
    }

    // MARK: - CommandBarAction Variants

    func test_item_action_dispatch_storesCommand() {
        // Arrange & Act
        let item = makeCommandBarItem(action: .dispatch(.toggleSidebar))

        // Assert
        if case .dispatch(let command) = item.action {
            XCTAssertEqual(command, .toggleSidebar)
        } else {
            XCTFail("Expected .dispatch action")
        }
    }

    func test_item_action_dispatchTargeted_storesTargetAndType() {
        // Arrange
        let targetId = UUID()

        // Act
        let item = makeCommandBarItem(action: .dispatchTargeted(.closeTab, target: targetId, targetType: .tab))

        // Assert
        if case .dispatchTargeted(let command, let target, let targetType) = item.action {
            XCTAssertEqual(command, .closeTab)
            XCTAssertEqual(target, targetId)
            XCTAssertEqual(targetType, .tab)
        } else {
            XCTFail("Expected .dispatchTargeted action")
        }
    }

    func test_item_action_navigate_storesLevel() {
        // Arrange
        let level = makeCommandBarLevel(id: "nav-level", title: "Nav Level")

        // Act
        let item = makeCommandBarItem(action: .navigate(level))

        // Assert
        if case .navigate(let navigatedLevel) = item.action {
            XCTAssertEqual(navigatedLevel.id, "nav-level")
            XCTAssertEqual(navigatedLevel.title, "Nav Level")
        } else {
            XCTFail("Expected .navigate action")
        }
    }

    // MARK: - CommandBarItemGroup

    func test_group_storesProperties() {
        // Arrange
        let items = [makeCommandBarItem(id: "a"), makeCommandBarItem(id: "b")]

        // Act
        let group = CommandBarItemGroup(id: "pane", name: "Pane", priority: 2, items: items)

        // Assert
        XCTAssertEqual(group.id, "pane")
        XCTAssertEqual(group.name, "Pane")
        XCTAssertEqual(group.priority, 2)
        XCTAssertEqual(group.items.count, 2)
    }

    // MARK: - ShortcutKey Edge Cases

    func test_shortcutKey_fromKeyBinding_emptyKey_producesEmpty() {
        // Arrange
        let binding = KeyBinding(key: "", modifiers: [.command])

        // Act
        let keys = ShortcutKey.from(keyBinding: binding)

        // Assert — modifier + empty key uppercased
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys[0].symbol, "⌘")
        XCTAssertEqual(keys[1].symbol, "")
    }
}
