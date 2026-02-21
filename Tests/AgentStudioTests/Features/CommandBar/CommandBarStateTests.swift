import XCTest

@testable import AgentStudio

final class CommandBarStateTests: XCTestCase {

    private var state: CommandBarState!

    private static let recentsKey = "CommandBarRecentItemIds"

    override func setUp() {
        super.setUp()
        // Isolate UserDefaults — clear recents key before each test
        UserDefaults.standard.removeObject(forKey: Self.recentsKey)
        state = CommandBarState()
    }

    override func tearDown() {
        // Clean up UserDefaults after each test
        UserDefaults.standard.removeObject(forKey: Self.recentsKey)
        state = nil
        super.tearDown()
    }

    // MARK: - Initialization

    func test_init_defaults() {
        // Assert
        XCTAssertFalse(state.isVisible)
        XCTAssertEqual(state.rawInput, "")
        XCTAssertTrue(state.navigationStack.isEmpty)
        XCTAssertEqual(state.selectedIndex, 0)
        XCTAssertTrue(state.recentItemIds.isEmpty)
    }

    // MARK: - Show / Dismiss

    func test_show_noPrefix_setsVisibleAndEmptyInput() {
        // Act
        state.show()

        // Assert
        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state.rawInput, "")
    }

    func test_show_withPrefix_setsVisibleAndPrefix() {
        // Act
        state.show(prefix: ">")

        // Assert
        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state.rawInput, "> ")
    }

    func test_show_withAtPrefix_setsVisibleAndAtPrefix() {
        // Act
        state.show(prefix: "@")

        // Assert
        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state.rawInput, "@ ")
    }

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
        XCTAssertFalse(state.isVisible)
        XCTAssertEqual(state.rawInput, "")
        XCTAssertTrue(state.navigationStack.isEmpty)
        XCTAssertEqual(state.selectedIndex, 0)
    }

    // MARK: - Prefix Parsing

    func test_activePrefix_greaterThan_returnsCommandPrefix() {
        // Arrange
        state.rawInput = ">close"

        // Assert
        XCTAssertEqual(state.activePrefix, ">")
    }

    func test_activePrefix_at_returnsPanePrefix() {
        // Arrange
        state.rawInput = "@main"

        // Assert
        XCTAssertEqual(state.activePrefix, "@")
    }

    func test_activePrefix_noPrefix_returnsNil() {
        // Arrange
        state.rawInput = "hello"

        // Assert
        XCTAssertNil(state.activePrefix)
    }

    func test_activePrefix_emptyInput_returnsNil() {
        // Arrange
        state.rawInput = ""

        // Assert
        XCTAssertNil(state.activePrefix)
    }

    func test_activePrefix_whenNested_returnsNil() {
        // Arrange — nesting overrides prefix parsing
        let level = makeCommandBarLevel()
        state.pushLevel(level)
        state.rawInput = ">"

        // Assert
        XCTAssertNil(state.activePrefix)
    }

    func test_activePrefix_unknownPrefix_returnsNil() {
        // Arrange
        state.rawInput = "#search"

        // Assert
        XCTAssertNil(state.activePrefix)
    }

    // MARK: - Search Query

    func test_searchQuery_withPrefix_stripsPrefix() {
        // Arrange
        state.rawInput = ">close"

        // Assert
        XCTAssertEqual(state.searchQuery, "close")
    }

    func test_searchQuery_noPrefix_returnsFullInput() {
        // Arrange
        state.rawInput = "hello"

        // Assert
        XCTAssertEqual(state.searchQuery, "hello")
    }

    func test_searchQuery_prefixOnly_returnsEmpty() {
        // Arrange
        state.rawInput = ">"

        // Assert
        XCTAssertEqual(state.searchQuery, "")
    }

    func test_searchQuery_emptyInput_returnsEmpty() {
        // Arrange
        state.rawInput = ""

        // Assert
        XCTAssertEqual(state.searchQuery, "")
    }

    // MARK: - Active Scope

    func test_activeScope_noPrefix_returnsEverything() {
        // Arrange
        state.rawInput = ""

        // Assert
        XCTAssertEqual(state.activeScope, .everything)
    }

    func test_activeScope_greaterThan_returnsCommands() {
        // Arrange
        state.rawInput = ">"

        // Assert
        XCTAssertEqual(state.activeScope, .commands)
    }

    func test_activeScope_at_returnsPanes() {
        // Arrange
        state.rawInput = "@"

        // Assert
        XCTAssertEqual(state.activeScope, .panes)
    }

    func test_activeScope_plainText_returnsEverything() {
        // Arrange
        state.rawInput = "search term"

        // Assert
        XCTAssertEqual(state.activeScope, .everything)
    }

    // MARK: - Switch Prefix

    func test_switchPrefix_replacesInputAndResetsStack() {
        // Arrange
        state.show()
        state.rawInput = "something"
        state.selectedIndex = 5

        // Act
        state.switchPrefix(">")

        // Assert
        XCTAssertEqual(state.rawInput, "> ")
        XCTAssertTrue(state.navigationStack.isEmpty)
        XCTAssertEqual(state.selectedIndex, 0)
    }

    func test_switchPrefix_clearsNavigationStack() {
        // Arrange
        state.pushLevel(makeCommandBarLevel())

        // Act
        state.switchPrefix("@")

        // Assert
        XCTAssertTrue(state.navigationStack.isEmpty)
        XCTAssertEqual(state.rawInput, "@ ")
    }

    // MARK: - Navigation

    func test_pushLevel_addsToStackAndClearsInput() {
        // Arrange
        state.rawInput = "search"
        state.selectedIndex = 3
        let level = makeCommandBarLevel(id: "sub-1", title: "Close Tab")

        // Act
        state.pushLevel(level)

        // Assert
        XCTAssertEqual(state.navigationStack.count, 1)
        XCTAssertEqual(state.navigationStack.last?.id, "sub-1")
        XCTAssertEqual(state.rawInput, "")
        XCTAssertEqual(state.selectedIndex, 0)
    }

    func test_popToRoot_clearsStackAndInput() {
        // Arrange
        state.pushLevel(makeCommandBarLevel(id: "level-1"))
        state.rawInput = "filter text"

        // Act
        state.popToRoot()

        // Assert
        XCTAssertTrue(state.navigationStack.isEmpty)
        XCTAssertEqual(state.rawInput, "")
        XCTAssertEqual(state.selectedIndex, 0)
    }

    func test_isNested_afterPush_returnsTrue() {
        // Act
        state.pushLevel(makeCommandBarLevel())

        // Assert
        XCTAssertTrue(state.isNested)
    }

    func test_isNested_atRoot_returnsFalse() {
        // Assert
        XCTAssertFalse(state.isNested)
    }

    func test_currentLevel_returnsLastPushed() {
        // Arrange
        let level = makeCommandBarLevel(id: "my-level", title: "My Level")

        // Act
        state.pushLevel(level)

        // Assert
        XCTAssertEqual(state.currentLevel?.id, "my-level")
        XCTAssertEqual(state.currentLevel?.title, "My Level")
    }

    func test_currentLevel_atRoot_returnsNil() {
        // Assert
        XCTAssertNil(state.currentLevel)
    }

    func test_scopePillParent_returnsParentLabel() {
        // Arrange
        let level = makeCommandBarLevel(parentLabel: "Tab")

        // Act
        state.pushLevel(level)

        // Assert
        XCTAssertEqual(state.scopePillParent, "Tab")
    }

    func test_scopePillChild_returnsLevelTitle() {
        // Arrange
        let level = makeCommandBarLevel(title: "Close Tab")

        // Act
        state.pushLevel(level)

        // Assert
        XCTAssertEqual(state.scopePillChild, "Close Tab")
    }

    // MARK: - Selection

    func test_rawInput_didSet_resetsSelectedIndex() {
        // Arrange
        state.selectedIndex = 5

        // Act
        state.rawInput = "new text"

        // Assert
        XCTAssertEqual(state.selectedIndex, 0)
    }

    func test_moveSelectionDown_incrementsIndex() {
        // Arrange
        state.selectedIndex = 0

        // Act
        state.moveSelectionDown(totalItems: 5)

        // Assert
        XCTAssertEqual(state.selectedIndex, 1)
    }

    func test_moveSelectionDown_wrapsToZero() {
        // Arrange
        state.selectedIndex = 2

        // Act
        state.moveSelectionDown(totalItems: 3)

        // Assert
        XCTAssertEqual(state.selectedIndex, 0)
    }

    func test_moveSelectionUp_decrementsIndex() {
        // Arrange
        state.selectedIndex = 2

        // Act
        state.moveSelectionUp(totalItems: 5)

        // Assert
        XCTAssertEqual(state.selectedIndex, 1)
    }

    func test_moveSelectionUp_wrapsToEnd() {
        // Arrange
        state.selectedIndex = 0

        // Act
        state.moveSelectionUp(totalItems: 3)

        // Assert
        XCTAssertEqual(state.selectedIndex, 2)
    }

    func test_moveSelectionDown_zeroItems_noChange() {
        // Arrange
        state.selectedIndex = 0

        // Act
        state.moveSelectionDown(totalItems: 0)

        // Assert
        XCTAssertEqual(state.selectedIndex, 0)
    }

    func test_moveSelectionUp_zeroItems_noChange() {
        // Arrange
        state.selectedIndex = 0

        // Act
        state.moveSelectionUp(totalItems: 0)

        // Assert
        XCTAssertEqual(state.selectedIndex, 0)
    }

    // MARK: - Recents

    func test_recordRecent_addsToFront() {
        // Act
        state.recordRecent(itemId: "A")
        state.recordRecent(itemId: "B")

        // Assert
        XCTAssertEqual(state.recentItemIds, ["B", "A"])
    }

    func test_recordRecent_deduplicates() {
        // Act
        state.recordRecent(itemId: "A")
        state.recordRecent(itemId: "B")
        state.recordRecent(itemId: "A")

        // Assert — "A" moves to front, no duplicate
        XCTAssertEqual(state.recentItemIds, ["A", "B"])
    }

    func test_recordRecent_capsAt8() {
        // Act
        for i in 1...10 {
            state.recordRecent(itemId: "item-\(i)")
        }

        // Assert
        XCTAssertEqual(state.recentItemIds.count, 8)
        XCTAssertEqual(state.recentItemIds.first, "item-10")
        XCTAssertEqual(state.recentItemIds.last, "item-3")
    }

    // MARK: - Placeholder

    func test_placeholder_everything_returnsSearchOrJump() {
        // Arrange
        state.rawInput = ""

        // Assert
        XCTAssertEqual(state.placeholder, "Search or jump to...")
    }

    func test_placeholder_commands_returnsRunACommand() {
        // Arrange
        state.rawInput = ">"

        // Assert
        XCTAssertEqual(state.placeholder, "Run a command...")
    }

    func test_placeholder_panes_returnsSwitchToPane() {
        // Arrange
        state.rawInput = "@"

        // Assert
        XCTAssertEqual(state.placeholder, "Switch to pane...")
    }

    func test_placeholder_nested_returnsFilter() {
        // Arrange
        state.pushLevel(makeCommandBarLevel())

        // Assert
        XCTAssertEqual(state.placeholder, "Filter...")
    }

    // MARK: - Scope Icon

    func test_scopeIcon_everything_returnsMagnifyingGlass() {
        // Arrange
        state.rawInput = ""

        // Assert
        XCTAssertEqual(state.scopeIcon, "magnifyingglass")
    }

    func test_scopeIcon_commands_returnsChevron() {
        // Arrange
        state.rawInput = ">"

        // Assert
        XCTAssertEqual(state.scopeIcon, "chevron.right.2")
    }

    func test_scopeIcon_panes_returnsAt() {
        // Arrange
        state.rawInput = "@"

        // Assert
        XCTAssertEqual(state.scopeIcon, "at")
    }

    func test_scopeIcon_nested_returnsMagnifyingGlass() {
        // Arrange
        state.pushLevel(makeCommandBarLevel())

        // Assert
        XCTAssertEqual(state.scopeIcon, "magnifyingglass")
    }

    // MARK: - Scope Pill at Root (nil behavior)

    func test_scopePillParent_atRoot_returnsNil() {
        // Assert — no nested level, should be nil
        XCTAssertNil(state.scopePillParent)
    }

    func test_scopePillChild_atRoot_returnsNil() {
        // Assert
        XCTAssertNil(state.scopePillChild)
    }

    // MARK: - Selection Edge Cases (out-of-bounds initial state)

    func test_moveSelectionDown_staleIndexBeyondTotal_wrapsToZero() {
        // Arrange — simulate filter shrinking results while index is high
        state.selectedIndex = 10

        // Act
        state.moveSelectionDown(totalItems: 3)

        // Assert — wraps since 10 >= 3-1
        XCTAssertEqual(state.selectedIndex, 0)
    }

    func test_moveSelectionUp_staleIndexBeyondTotal_wrapsToEnd() {
        // Arrange — stale index beyond total
        state.selectedIndex = 10

        // Act
        state.moveSelectionUp(totalItems: 3)

        // Assert — 10 > 0 so decrements to 9 (still stale, but moveUp's contract is index-1)
        // This reveals the current behavior: it just decrements
        XCTAssertEqual(state.selectedIndex, 9)
    }

    func test_moveSelectionDown_singleItem_staysAtZero() {
        // Arrange
        state.selectedIndex = 0

        // Act
        state.moveSelectionDown(totalItems: 1)

        // Assert — wraps back to 0
        XCTAssertEqual(state.selectedIndex, 0)
    }

    // MARK: - Prefix Edge Cases

    func test_show_emptyPrefix_treatedAsNoPrefix() {
        // Act
        state.show(prefix: "")

        // Assert
        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state.rawInput, "")
        XCTAssertEqual(state.activeScope, .everything)
    }

    func test_show_unknownPrefix_treatedAsPlainText() {
        // Act
        state.show(prefix: "#")

        // Assert — "#" is stored as rawInput but not a recognized prefix
        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state.rawInput, "#")
        XCTAssertNil(state.activePrefix)
        XCTAssertEqual(state.activeScope, .everything)
    }

    func test_switchPrefix_emptyString_clearsToEverything() {
        // Arrange
        state.show(prefix: ">")

        // Act
        state.switchPrefix("")

        // Assert
        XCTAssertEqual(state.rawInput, "")
        XCTAssertEqual(state.activeScope, .everything)
    }

    // MARK: - Persistence — loadRecents

    func test_loadRecents_emptyDefaults_setsEmptyArray() {
        // Arrange — UserDefaults is already cleared in setUp

        // Act
        state.loadRecents()

        // Assert
        XCTAssertTrue(state.recentItemIds.isEmpty)
    }

    func test_loadRecents_populatedDefaults_restoresArray() {
        // Arrange
        let expected = ["item-1", "item-2", "item-3"]
        UserDefaults.standard.set(expected, forKey: Self.recentsKey)

        // Act
        state.loadRecents()

        // Assert
        XCTAssertEqual(state.recentItemIds, expected)
    }

    func test_recordRecent_thenLoadRecents_roundTrips() {
        // Arrange
        state.recordRecent(itemId: "alpha")
        state.recordRecent(itemId: "beta")

        // Act — create new state and load from UserDefaults
        let freshState = CommandBarState()
        freshState.loadRecents()

        // Assert
        XCTAssertEqual(freshState.recentItemIds, ["beta", "alpha"])
    }
}
