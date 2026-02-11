import AppKit
import XCTest
@testable import AgentStudio

final class CommandBarPanelControllerTests: XCTestCase {

    private var controller: CommandBarPanelController!
    private var window: NSWindow!

    override func setUp() {
        super.setUp()
        controller = CommandBarPanelController()
        // Offscreen window — never displayed, lightweight test double
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
    }

    override func tearDown() {
        controller.dismiss()
        controller = nil
        window = nil
        super.tearDown()
    }

    // MARK: - Initialization

    func test_init_stateIsNotVisible() {
        // Assert
        XCTAssertFalse(controller.state.isVisible)
        XCTAssertEqual(controller.state.rawInput, "")
        XCTAssertTrue(controller.state.navigationStack.isEmpty)
    }

    // MARK: - Show via Public API

    func test_show_noPrefix_setsStateVisible() {
        // Act
        controller.show(parentWindow: window)

        // Assert
        XCTAssertTrue(controller.state.isVisible)
        XCTAssertEqual(controller.state.rawInput, "")
        XCTAssertEqual(controller.state.activeScope, .everything)
    }

    func test_show_withCommandPrefix_setsCommandScope() {
        // Act
        controller.show(prefix: ">", parentWindow: window)

        // Assert
        XCTAssertTrue(controller.state.isVisible)
        XCTAssertEqual(controller.state.rawInput, ">")
        XCTAssertEqual(controller.state.activeScope, .commands)
    }

    func test_show_withPanePrefix_setsPaneScope() {
        // Act
        controller.show(prefix: "@", parentWindow: window)

        // Assert
        XCTAssertTrue(controller.state.isVisible)
        XCTAssertEqual(controller.state.rawInput, "@")
        XCTAssertEqual(controller.state.activeScope, .panes)
    }

    // MARK: - Dismiss via Public API

    func test_dismiss_afterShow_resetsState() {
        // Arrange
        controller.show(parentWindow: window)
        XCTAssertTrue(controller.state.isVisible)

        // Act
        controller.dismiss()

        // Assert
        XCTAssertFalse(controller.state.isVisible)
        XCTAssertEqual(controller.state.rawInput, "")
    }

    func test_dismiss_whenNotVisible_noOp() {
        // Arrange — not visible
        XCTAssertFalse(controller.state.isVisible)

        // Act — should not crash or change state
        controller.dismiss()

        // Assert
        XCTAssertFalse(controller.state.isVisible)
    }

    // MARK: - Toggle Behavior (same prefix → dismiss)

    func test_show_samePrefixTwice_togglesOff() {
        // Arrange — show with no prefix
        controller.show(parentWindow: window)
        XCTAssertTrue(controller.state.isVisible)

        // Act — show again with same prefix (nil)
        controller.show(parentWindow: window)

        // Assert — should dismiss (toggle behavior)
        XCTAssertFalse(controller.state.isVisible)
    }

    func test_show_sameCommandPrefixTwice_togglesOff() {
        // Arrange
        controller.show(prefix: ">", parentWindow: window)
        XCTAssertTrue(controller.state.isVisible)

        // Act
        controller.show(prefix: ">", parentWindow: window)

        // Assert
        XCTAssertFalse(controller.state.isVisible)
    }

    // MARK: - Switch Behavior (different prefix → switch in-place)

    func test_show_differentPrefix_switchesInPlace() {
        // Arrange — open with no prefix
        controller.show(parentWindow: window)
        XCTAssertEqual(controller.state.activeScope, .everything)

        // Act — show with command prefix
        controller.show(prefix: ">", parentWindow: window)

        // Assert — switched, still visible
        XCTAssertTrue(controller.state.isVisible)
        XCTAssertEqual(controller.state.rawInput, ">")
        XCTAssertEqual(controller.state.activeScope, .commands)
    }

    func test_show_switchFromCommandToPane_switchesInPlace() {
        // Arrange — open with ">"
        controller.show(prefix: ">", parentWindow: window)
        XCTAssertEqual(controller.state.activeScope, .commands)

        // Act — switch to "@"
        controller.show(prefix: "@", parentWindow: window)

        // Assert
        XCTAssertTrue(controller.state.isVisible)
        XCTAssertEqual(controller.state.rawInput, "@")
        XCTAssertEqual(controller.state.activeScope, .panes)
    }

    // MARK: - Full Lifecycle

    func test_fullLifecycle_showQueryPushDismiss() {
        // Act — show
        controller.show(prefix: ">", parentWindow: window)
        XCTAssertTrue(controller.state.isVisible)

        // Act — simulate user typing a query
        controller.state.rawInput = ">close"
        XCTAssertEqual(controller.state.searchQuery, "close")

        // Act — push into nested level
        let level = makeCommandBarLevel(id: "close-tab", title: "Close Tab", parentLabel: "Tab")
        controller.state.pushLevel(level)
        XCTAssertTrue(controller.state.isNested)

        // Act — dismiss via public API
        controller.dismiss()

        // Assert — everything reset
        XCTAssertFalse(controller.state.isVisible)
        XCTAssertFalse(controller.state.isNested)
        XCTAssertEqual(controller.state.rawInput, "")
        XCTAssertEqual(controller.state.selectedIndex, 0)
    }
}
