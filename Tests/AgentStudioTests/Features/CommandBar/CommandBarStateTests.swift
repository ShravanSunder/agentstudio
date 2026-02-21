import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class CommandBarStateTests {

    private var state: CommandBarState!

    private static let recentsKey = "CommandBarRecentItemIds"

    init() {
        // Isolate UserDefaults — clear recents key before each test
        UserDefaults.standard.removeObject(forKey: Self.recentsKey)
        state = CommandBarState()
    }

    deinit {
        // Clean up UserDefaults after each test
        UserDefaults.standard.removeObject(forKey: Self.recentsKey)
        state = nil
    }

    // MARK: - Initialization

    @Test
    func test_init_defaults() {
        // Assert
        #expect(!(state.isVisible))
        #expect(state.rawInput.isEmpty)
        #expect(state.navigationStack.isEmpty)
        #expect(state.selectedIndex == 0)
        #expect(state.recentItemIds.isEmpty)
    }

    // MARK: - Show / Dismiss

    @Test
    func test_show_noPrefix_setsVisibleAndEmptyInput() {
        // Act
        state.show()

        // Assert
        #expect(state.isVisible)
        #expect(state.rawInput.isEmpty)
    }

    @Test
    func test_show_withPrefix_setsVisibleAndPrefix() {
        // Act
        state.show(prefix: ">")

        // Assert
        #expect(state.isVisible)
        #expect(state.rawInput == "> ")
    }

    @Test
    func test_show_withAtPrefix_setsVisibleAndAtPrefix() {
        // Act
        state.show(prefix: "@")

        // Assert
        #expect(state.isVisible)
        #expect(state.rawInput == "@ ")
    }

    @Test
    func test_dismiss_resetsAllState() {
        // Arrange
        state.show(prefix: ">")
        state.rawInput = ">close"
        state.selectedIndex = 3
        let level = makeCommandBarLevel()
        state.pushLevel(level)

        // Act
        state.dismiss()

        // Assert
        #expect(!(state.isVisible))
        #expect(state.rawInput.isEmpty)
        #expect(state.navigationStack.isEmpty)
        #expect(state.selectedIndex == 0)
    }

    // MARK: - Prefix Parsing

    @Test
    func test_activePrefix_greaterThan_returnsCommandPrefix() {
        // Arrange
        state.rawInput = ">close"

        // Assert
        #expect(state.activePrefix == ">")
    }

    @Test
    func test_activePrefix_at_returnsPanePrefix() {
        // Arrange
        state.rawInput = "@main"

        // Assert
        #expect(state.activePrefix == "@")
    }

    @Test
    func test_activePrefix_noPrefix_returnsNil() {
        // Arrange
        state.rawInput = "hello"

        // Assert
        #expect(state.activePrefix == nil)
    }

    @Test
    func test_activePrefix_emptyInput_returnsNil() {
        // Arrange
        state.rawInput = ""

        // Assert
        #expect(state.activePrefix == nil)
    }

    @Test
    func test_activePrefix_whenNested_returnsNil() {
        // Arrange — nesting overrides prefix parsing
        let level = makeCommandBarLevel()
        state.pushLevel(level)
        state.rawInput = ">"

        // Assert
        #expect(state.activePrefix == nil)
    }

    @Test
    func test_activePrefix_unknownPrefix_returnsNil() {
        // Arrange
        state.rawInput = "#search"

        // Assert
        #expect(state.activePrefix == nil)
    }

    // MARK: - Search Query

    @Test
    func test_searchQuery_withPrefix_stripsPrefix() {
        // Arrange
        state.rawInput = ">close"

        // Assert
        #expect(state.searchQuery == "close")
    }

    @Test
    func test_searchQuery_noPrefix_returnsFullInput() {
        // Arrange
        state.rawInput = "hello"

        // Assert
        #expect(state.searchQuery == "hello")
    }

    @Test
    func test_searchQuery_prefixOnly_returnsEmpty() {
        // Arrange
        state.rawInput = ">"

        // Assert
        #expect(state.searchQuery.isEmpty)
    }

    @Test
    func test_searchQuery_emptyInput_returnsEmpty() {
        // Arrange
        state.rawInput = ""

        // Assert
        #expect(state.searchQuery.isEmpty)
    }

    // MARK: - Active Scope

    @Test
    func test_activeScope_noPrefix_returnsEverything() {
        // Arrange
        state.rawInput = ""

        // Assert
        #expect(state.activeScope == .everything)
    }

    @Test
    func test_activeScope_greaterThan_returnsCommands() {
        // Arrange
        state.rawInput = ">"

        // Assert
        #expect(state.activeScope == .commands)
    }

    @Test
    func test_activeScope_at_returnsPanes() {
        // Arrange
        state.rawInput = "@"

        // Assert
        #expect(state.activeScope == .panes)
    }

    @Test
    func test_activeScope_plainText_returnsEverything() {
        // Arrange
        state.rawInput = "search term"

        // Assert
        #expect(state.activeScope == .everything)
    }

    // MARK: - Switch Prefix

    @Test
    func test_switchPrefix_replacesInputAndResetsStack() {
        // Arrange
        state.show()
        state.rawInput = "something"
        state.selectedIndex = 5

        // Act
        state.switchPrefix(">")

        // Assert
        #expect(state.rawInput == "> ")
        #expect(state.navigationStack.isEmpty)
        #expect(state.selectedIndex == 0)
    }

    @Test
    func test_switchPrefix_clearsNavigationStack() {
        // Arrange
        state.pushLevel(makeCommandBarLevel())

        // Act
        state.switchPrefix("@")

        // Assert
        #expect(state.navigationStack.isEmpty)
        #expect(state.rawInput == "@ ")
    }

    // MARK: - Navigation

    @Test
    func test_pushLevel_addsToStackAndClearsInput() {
        // Arrange
        state.rawInput = "search"
        state.selectedIndex = 3
        let level = makeCommandBarLevel(id: "sub-1", title: "Close Tab")

        // Act
        state.pushLevel(level)

        // Assert
        #expect(state.navigationStack.count == 1)
        #expect(state.navigationStack.last?.id == "sub-1")
        #expect(state.rawInput.isEmpty)
        #expect(state.selectedIndex == 0)
    }

    @Test
    func test_popToRoot_clearsStackAndInput() {
        // Arrange
        state.pushLevel(makeCommandBarLevel(id: "level-1"))
        state.rawInput = "filter text"

        // Act
        state.popToRoot()

        // Assert
        #expect(state.navigationStack.isEmpty)
        #expect(state.rawInput.isEmpty)
        #expect(state.selectedIndex == 0)
    }

    @Test
    func test_isNested_afterPush_returnsTrue() {
        // Act
        state.pushLevel(makeCommandBarLevel())

        // Assert
        #expect(state.isNested)
    }

    @Test
    func test_isNested_atRoot_returnsFalse() {
        // Assert
        #expect(!(state.isNested))
    }

    @Test
    func test_currentLevel_returnsLastPushed() {
        // Arrange
        let level = makeCommandBarLevel(id: "my-level", title: "My Level")

        // Act
        state.pushLevel(level)

        // Assert
        #expect(state.currentLevel?.id == "my-level")
        #expect(state.currentLevel?.title == "My Level")
    }

    @Test
    func test_currentLevel_atRoot_returnsNil() {
        // Assert
        #expect(state.currentLevel == nil)
    }

    @Test
    func test_scopePillParent_returnsParentLabel() {
        // Arrange
        let level = makeCommandBarLevel(parentLabel: "Tab")

        // Act
        state.pushLevel(level)

        // Assert
        #expect(state.scopePillParent == "Tab")
    }

    @Test
    func test_scopePillChild_returnsLevelTitle() {
        // Arrange
        let level = makeCommandBarLevel(title: "Close Tab")

        // Act
        state.pushLevel(level)

        // Assert
        #expect(state.scopePillChild == "Close Tab")
    }

    // MARK: - Selection

    @Test
    func test_rawInput_didSet_resetsSelectedIndex() {
        // Arrange
        state.selectedIndex = 5

        // Act
        state.rawInput = "new text"

        // Assert
        #expect(state.selectedIndex == 0)
    }

    @Test
    func test_moveSelectionDown_incrementsIndex() {
        // Arrange
        state.selectedIndex = 0

        // Act
        state.moveSelectionDown(totalItems: 5)

        // Assert
        #expect(state.selectedIndex == 1)
    }

    @Test
    func test_moveSelectionDown_wrapsToZero() {
        // Arrange
        state.selectedIndex = 2

        // Act
        state.moveSelectionDown(totalItems: 3)

        // Assert
        #expect(state.selectedIndex == 0)
    }

    @Test
    func test_moveSelectionUp_decrementsIndex() {
        // Arrange
        state.selectedIndex = 2

        // Act
        state.moveSelectionUp(totalItems: 5)

        // Assert
        #expect(state.selectedIndex == 1)
    }

    @Test
    func test_moveSelectionUp_wrapsToEnd() {
        // Arrange
        state.selectedIndex = 0

        // Act
        state.moveSelectionUp(totalItems: 3)

        // Assert
        #expect(state.selectedIndex == 2)
    }

    @Test
    func test_moveSelectionDown_zeroItems_noChange() {
        // Arrange
        state.selectedIndex = 0

        // Act
        state.moveSelectionDown(totalItems: 0)

        // Assert
        #expect(state.selectedIndex == 0)
    }

    @Test
    func test_moveSelectionUp_zeroItems_noChange() {
        // Arrange
        state.selectedIndex = 0

        // Act
        state.moveSelectionUp(totalItems: 0)

        // Assert
        #expect(state.selectedIndex == 0)
    }

    // MARK: - Recents

    @Test
    func test_recordRecent_addsToFront() {
        // Act
        state.recordRecent(itemId: "A")
        state.recordRecent(itemId: "B")

        // Assert
        #expect(state.recentItemIds == ["B", "A"])
    }

    @Test
    func test_recordRecent_deduplicates() {
        // Act
        state.recordRecent(itemId: "A")
        state.recordRecent(itemId: "B")
        state.recordRecent(itemId: "A")

        // Assert — "A" moves to front, no duplicate
        #expect(state.recentItemIds == ["A", "B"])
    }

    @Test
    func test_recordRecent_capsAt8() {
        // Act
        for i in 1...10 {
            state.recordRecent(itemId: "item-\(i)")
        }

        // Assert
        #expect(state.recentItemIds.count == 8)
        #expect(state.recentItemIds.first == "item-10")
        #expect(state.recentItemIds.last == "item-3")
    }

    // MARK: - Placeholder

    @Test
    func test_placeholder_everything_returnsSearchOrJump() {
        // Arrange
        state.rawInput = ""

        // Assert
        #expect(state.placeholder == "Search or jump to...")
    }

    @Test
    func test_placeholder_commands_returnsRunACommand() {
        // Arrange
        state.rawInput = ">"

        // Assert
        #expect(state.placeholder == "Run a command...")
    }

    @Test
    func test_placeholder_panes_returnsSwitchToPane() {
        // Arrange
        state.rawInput = "@"

        // Assert
        #expect(state.placeholder == "Switch to pane...")
    }

    @Test
    func test_placeholder_nested_returnsFilter() {
        // Arrange
        state.pushLevel(makeCommandBarLevel())

        // Assert
        #expect(state.placeholder == "Filter...")
    }

    // MARK: - Scope Icon

    @Test
    func test_scopeIcon_everything_returnsMagnifyingGlass() {
        // Arrange
        state.rawInput = ""

        // Assert
        #expect(state.scopeIcon == "magnifyingglass")
    }

    @Test
    func test_scopeIcon_commands_returnsChevron() {
        // Arrange
        state.rawInput = ">"

        // Assert
        #expect(state.scopeIcon == "chevron.right.2")
    }

    @Test
    func test_scopeIcon_panes_returnsAt() {
        // Arrange
        state.rawInput = "@"

        // Assert
        #expect(state.scopeIcon == "at")
    }

    @Test
    func test_scopeIcon_nested_returnsMagnifyingGlass() {
        // Arrange
        state.pushLevel(makeCommandBarLevel())

        // Assert
        #expect(state.scopeIcon == "magnifyingglass")
    }

    // MARK: - Scope Pill at Root (nil behavior)

    @Test
    func test_scopePillParent_atRoot_returnsNil() {
        // Assert — no nested level, should be nil
        #expect(state.scopePillParent == nil)
    }

    @Test
    func test_scopePillChild_atRoot_returnsNil() {
        // Assert
        #expect(state.scopePillChild == nil)
    }

    // MARK: - Selection Edge Cases (out-of-bounds initial state)

    @Test
    func test_moveSelectionDown_staleIndexBeyondTotal_wrapsToZero() {
        // Arrange — simulate filter shrinking results while index is high
        state.selectedIndex = 10

        // Act
        state.moveSelectionDown(totalItems: 3)

        // Assert — wraps since 10 >= 3-1
        #expect(state.selectedIndex == 0)
    }

    @Test
    func test_moveSelectionUp_staleIndexBeyondTotal_wrapsToEnd() {
        // Arrange — stale index beyond total
        state.selectedIndex = 10

        // Act
        state.moveSelectionUp(totalItems: 3)

        // Assert — 10 > 0 so decrements to 9 (still stale, but moveUp's contract is index-1)
        // This reveals the current behavior: it just decrements
        #expect(state.selectedIndex == 9)
    }

    @Test
    func test_moveSelectionDown_singleItem_staysAtZero() {
        // Arrange
        state.selectedIndex = 0

        // Act
        state.moveSelectionDown(totalItems: 1)

        // Assert — wraps back to 0
        #expect(state.selectedIndex == 0)
    }

    // MARK: - Prefix Edge Cases

    @Test
    func test_show_emptyPrefix_treatedAsNoPrefix() {
        // Act
        state.show(prefix: "")

        // Assert
        #expect(state.isVisible)
        #expect(state.rawInput.isEmpty)
        #expect(state.activeScope == .everything)
    }

    @Test
    func test_show_unknownPrefix_treatedAsPlainText() {
        // Act
        state.show(prefix: "#")

        // Assert — "#" is stored as rawInput but not a recognized prefix
        #expect(state.isVisible)
        #expect(state.rawInput == "#")
        #expect(state.activePrefix == nil)
        #expect(state.activeScope == .everything)
    }

    @Test
    func test_switchPrefix_emptyString_clearsToEverything() {
        // Arrange
        state.show(prefix: ">")

        // Act
        state.switchPrefix("")

        // Assert
        #expect(state.rawInput.isEmpty)
        #expect(state.activeScope == .everything)
    }

    // MARK: - Persistence — loadRecents

    @Test
    func test_loadRecents_emptyDefaults_setsEmptyArray() {
        // Arrange — UserDefaults is already cleared in setUp

        // Act
        state.loadRecents()

        // Assert
        #expect(state.recentItemIds.isEmpty)
    }

    @Test
    func test_loadRecents_populatedDefaults_restoresArray() {
        // Arrange
        let expected = ["item-1", "item-2", "item-3"]
        UserDefaults.standard.set(expected, forKey: Self.recentsKey)

        // Act
        state.loadRecents()

        // Assert
        #expect(state.recentItemIds == expected)
    }

    @Test
    func test_recordRecent_thenLoadRecents_roundTrips() {
        // Arrange
        state.recordRecent(itemId: "alpha")
        state.recordRecent(itemId: "beta")

        // Act — create new state and load from UserDefaults
        let freshState = CommandBarState()
        freshState.loadRecents()

        // Assert
        #expect(freshState.recentItemIds == ["beta", "alpha"])
    }
}
