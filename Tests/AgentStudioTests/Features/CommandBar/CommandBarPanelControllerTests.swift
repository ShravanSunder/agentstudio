import AppKit
import Testing
import Foundation

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct CommandBarPanelControllerTests {

    private let window: NSWindow

    init() {
        // Offscreen window — never displayed, lightweight test double
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
    }

    @Test
    func test_init_stateIsNotVisible() {
        let controller = CommandBarPanelController(store: WorkspaceStore(), dispatcher: .shared)

        // Assert
        #expect(!controller.state.isVisible)
        #expect(controller.state.rawInput == "")
        #expect(controller.state.navigationStack.isEmpty)
    }

    // MARK: - Show via Public API

    @Test
    func test_show_noPrefix_setsStateVisible() {
        let controller = CommandBarPanelController(store: WorkspaceStore(), dispatcher: .shared)

        // Act
        controller.show(parentWindow: window)

        // Assert
        #expect(controller.state.isVisible)
        #expect(controller.state.rawInput == "")
        #expect(controller.state.activeScope == .everything)
    }

    @Test
    func test_show_withCommandPrefix_setsCommandScope() {
        let controller = CommandBarPanelController(store: WorkspaceStore(), dispatcher: .shared)

        // Act
        controller.show(prefix: ">", parentWindow: window)

        // Assert
        #expect(controller.state.isVisible)
        #expect(controller.state.rawInput == "> ")
        #expect(controller.state.activeScope == .commands)
    }

    @Test
    func test_show_withPanePrefix_setsPaneScope() {
        let controller = CommandBarPanelController(store: WorkspaceStore(), dispatcher: .shared)

        // Act
        controller.show(prefix: "@", parentWindow: window)

        // Assert
        #expect(controller.state.isVisible)
        #expect(controller.state.rawInput == "@ ")
        #expect(controller.state.activeScope == .panes)
    }

    // MARK: - Dismiss via Public API

    @Test
    func test_dismiss_afterShow_resetsState() {
        let controller = CommandBarPanelController(store: WorkspaceStore(), dispatcher: .shared)
        #expect(!controller.state.isVisible)

        // Arrange
        controller.show(parentWindow: window)
        #expect(controller.state.isVisible)

        // Act
        controller.dismiss()

        // Assert
        #expect(!controller.state.isVisible)
        #expect(controller.state.rawInput == "")
    }

    @Test
    func test_dismiss_whenNotVisible_noOp() {
        let controller = CommandBarPanelController(store: WorkspaceStore(), dispatcher: .shared)

        // Arrange — not visible
        #expect(!controller.state.isVisible)

        // Act — should not crash or change state
        controller.dismiss()

        // Assert
        #expect(!controller.state.isVisible)
    }

    // MARK: - Toggle Behavior (same prefix → dismiss)

    @Test
    func test_show_samePrefixTwice_togglesOff() {
        let controller = CommandBarPanelController(store: WorkspaceStore(), dispatcher: .shared)

        // Arrange — show with no prefix
        controller.show(parentWindow: window)
        #expect(controller.state.isVisible)

        // Act — show again with same prefix (nil)
        controller.show(parentWindow: window)

        // Assert — should dismiss (toggle behavior)
        #expect(!controller.state.isVisible)
    }

    @Test
    func test_show_sameCommandPrefixTwice_togglesOff() {
        let controller = CommandBarPanelController(store: WorkspaceStore(), dispatcher: .shared)

        // Arrange
        controller.show(prefix: ">", parentWindow: window)
        #expect(controller.state.isVisible)

        // Act
        controller.show(prefix: ">", parentWindow: window)

        // Assert
        #expect(!controller.state.isVisible)
    }

    // MARK: - Switch Behavior (different prefix → switch in-place)

    @Test
    func test_show_differentPrefix_switchesInPlace() {
        let controller = CommandBarPanelController(store: WorkspaceStore(), dispatcher: .shared)

        // Arrange — open with no prefix
        controller.show(parentWindow: window)
        #expect(controller.state.activeScope == .everything)

        // Act — show with command prefix
        controller.show(prefix: ">", parentWindow: window)

        // Assert — switched, still visible
        #expect(controller.state.isVisible)
        #expect(controller.state.rawInput == "> ")
        #expect(controller.state.activeScope == .commands)
    }

    @Test
    func test_show_switchFromCommandToPane_switchesInPlace() {
        let controller = CommandBarPanelController(store: WorkspaceStore(), dispatcher: .shared)

        // Arrange — open with ">"
        controller.show(prefix: ">", parentWindow: window)
        #expect(controller.state.activeScope == .commands)

        // Act — switch to "@"
        controller.show(prefix: "@", parentWindow: window)

        // Assert
        #expect(controller.state.isVisible)
        #expect(controller.state.rawInput == "@ ")
        #expect(controller.state.activeScope == .panes)
    }

    // MARK: - Full Lifecycle

    @Test
    func test_fullLifecycle_showQueryPushDismiss() {
        let controller = CommandBarPanelController(store: WorkspaceStore(), dispatcher: .shared)

        // Act — show
        controller.show(prefix: ">", parentWindow: window)
        #expect(controller.state.isVisible)

        // Act — simulate user typing a query
        controller.state.rawInput = ">close"
        #expect(controller.state.searchQuery == "close")

        // Act — push into nested level
        let level = makeCommandBarLevel(id: "close-tab", title: "Close Tab", parentLabel: "Tab")
        controller.state.pushLevel(level)
        #expect(controller.state.isNested)

        // Act — dismiss via public API
        controller.dismiss()

        // Assert — everything reset
        #expect(!controller.state.isVisible)
        #expect(!controller.state.isNested)
        #expect(controller.state.rawInput == "")
        #expect(controller.state.selectedIndex == 0)
    }
}
