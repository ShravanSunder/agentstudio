import Testing
import Foundation

@testable import AgentStudio

@Suite(.serialized)
struct CommandBarItemTests {

    // MARK: - ShortcutKey from KeyBinding

    @Test
    func test_shortcutKey_fromKeyBinding_commandW() {
        // Arrange
        let binding = KeyBinding(key: "w", modifiers: [.command])

        // Act
        let keys = ShortcutKey.from(keyBinding: binding)

        // Assert
        #expect(keys.count == 2)
        #expect(keys[0].symbol == "⌘")
        #expect(keys[1].symbol == "W")
    }

    @Test
    func test_shortcutKey_fromKeyBinding_commandShiftO() {
        // Arrange
        let binding = KeyBinding(key: "O", modifiers: [.command, .shift])

        // Act
        let keys = ShortcutKey.from(keyBinding: binding)

        // Assert
        #expect(keys.count == 3)
        #expect(keys[0].symbol == "⌘")
        #expect(keys[1].symbol == "⇧")
        #expect(keys[2].symbol == "O")
    }

    @Test
    func test_shortcutKey_fromKeyBinding_allModifiers() {
        // Arrange
        let binding = KeyBinding(key: "k", modifiers: [.command, .shift, .option, .control])

        // Act
        let keys = ShortcutKey.from(keyBinding: binding)

        // Assert — order: command, shift, option, control, then key
        #expect(keys.count == 5)
        #expect(keys[0].symbol == "⌘")
        #expect(keys[1].symbol == "⇧")
        #expect(keys[2].symbol == "⌥")
        #expect(keys[3].symbol == "⌃")
        #expect(keys[4].symbol == "K")
    }

    @Test
    func test_shortcutKey_fromKeyBinding_noModifiers() {
        // Arrange
        let binding = KeyBinding(key: "p", modifiers: [])

        // Act
        let keys = ShortcutKey.from(keyBinding: binding)

        // Assert
        #expect(keys.count == 1)
        #expect(keys[0].symbol == "P")
    }

    @Test
    func test_shortcutKey_hashable_sameSymbolNotEqual() {
        // Arrange — two ShortcutKeys with same symbol get different UUIDs
        let key1 = ShortcutKey(symbol: "⌘")
        let key2 = ShortcutKey(symbol: "⌘")

        // Assert — they are not equal because id (UUID) differs
        #expect(key1 != key2)
    }

    // MARK: - CommandBarItem Init

    @Test
    func test_item_init_defaults() {
        // Arrange & Act
        let item = makeCommandBarItem()

        // Assert
        #expect(item.id == "test-item")
        #expect(item.title == "Test Item")
        #expect(item.subtitle == nil)
        #expect(item.icon == "terminal")
        #expect(item.iconColor == nil)
        #expect(item.shortcutKeys == nil)
        #expect(item.group == "Commands")
        #expect(item.groupPriority == 3)
        #expect(item.keywords.isEmpty)
        #expect(!item.hasChildren)
    }

    @Test
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
        #expect(item.id == "close-tab")
        #expect(item.title == "Close Tab")
        #expect(item.subtitle == "Tab 1")
        #expect(item.icon == "xmark")
        #expect(item.iconColor == .red)
        #expect(item.shortcutKeys?.count == 2)
        #expect(item.group == "Tab")
        #expect(item.groupPriority == 1)
        #expect(item.keywords == ["close", "remove"])
        #expect(item.hasChildren)
    }

    // MARK: - CommandBarLevel Init

    @Test
    func test_level_init_withParentLabel() {
        // Arrange & Act
        let level = makeCommandBarLevel(
            id: "tab-close",
            title: "Close Tab",
            parentLabel: "Tab"
        )

        // Assert
        #expect(level.id == "tab-close")
        #expect(level.title == "Close Tab")
        #expect(level.parentLabel == "Tab")
        #expect(level.items.isEmpty)
    }

    @Test
    func test_level_init_withoutParentLabel() {
        // Arrange & Act
        let level = CommandBarLevel(id: "root", title: "Root", items: [])

        // Assert
        #expect(level.parentLabel == nil)
    }

    // MARK: - CommandBarAction Variants

    @Test
    func test_item_action_dispatch_storesCommand() {
        // Arrange & Act
        let item = makeCommandBarItem(action: .dispatch(.toggleSidebar))

        // Assert
        if case .dispatch(let command) = item.action {
            #expect(command == .toggleSidebar)
        } else {
            Issue.record("Expected .dispatch action")
        }
    }

    @Test
    func test_item_action_dispatchTargeted_storesTargetAndType() {
        // Arrange
        let targetId = UUID()

        // Act
        let item = makeCommandBarItem(action: .dispatchTargeted(.closeTab, target: targetId, targetType: .tab))

        // Assert
        if case .dispatchTargeted(let command, let target, let targetType) = item.action {
            #expect(command == .closeTab)
            #expect(target == targetId)
            #expect(targetType == .tab)
        } else {
            Issue.record("Expected .dispatchTargeted action")
        }
    }

    @Test
    func test_item_action_navigate_storesLevel() {
        // Arrange
        let level = makeCommandBarLevel(id: "nav-level", title: "Nav Level")

        // Act
        let item = makeCommandBarItem(action: .navigate(level))

        // Assert
        if case .navigate(let navigatedLevel) = item.action {
            #expect(navigatedLevel.id == "nav-level")
            #expect(navigatedLevel.title == "Nav Level")
        } else {
            Issue.record("Expected .navigate action")
        }
    }

    // MARK: - CommandBarItemGroup

    @Test
    func test_group_storesProperties() {
        // Arrange
        let items = [makeCommandBarItem(id: "a"), makeCommandBarItem(id: "b")]

        // Act
        let group = CommandBarItemGroup(id: "pane", name: "Pane", priority: 2, items: items)

        // Assert
        #expect(group.id == "pane")
        #expect(group.name == "Pane")
        #expect(group.priority == 2)
        #expect(group.items.count == 2)
    }

    // MARK: - ShortcutKey Edge Cases

    @Test
    func test_shortcutKey_fromKeyBinding_emptyKey_producesEmpty() {
        // Arrange
        let binding = KeyBinding(key: "", modifiers: [.command])

        // Act
        let keys = ShortcutKey.from(keyBinding: binding)

        // Assert — modifier + empty key uppercased
        #expect(keys.count == 2)
        #expect(keys[0].symbol == "⌘")
        #expect(keys[1].symbol == "")
    }
}
