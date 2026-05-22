import AppKit
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct CommandBarPanelControllerTests {

    private let window: NSWindow

    init() {
        installTestAtomRegistryIfNeeded()
        installTestAtomRegistryIfNeeded()
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
        let controller = CommandBarPanelController(
            store: WorkspaceStore(), repoCache: RepoCacheAtom(), dispatcher: .shared)

        // Assert
        #expect(!controller.state.isVisible)
        #expect(controller.state.rawInput.isEmpty)
        #expect(controller.state.navigationStack.isEmpty)
    }

    // MARK: - Show via Public API

    @Test
    func test_show_noPrefix_setsStateVisible() {
        let controller = CommandBarPanelController(
            store: WorkspaceStore(), repoCache: RepoCacheAtom(), dispatcher: .shared)

        // Act
        controller.show(parentWindow: window)

        // Assert
        #expect(controller.state.isVisible)
        #expect(controller.state.rawInput.isEmpty)
        #expect(controller.state.activeScope == .everything)
    }

    @Test
    func test_show_withCommandPrefix_setsCommandScope() {
        let controller = CommandBarPanelController(
            store: WorkspaceStore(), repoCache: RepoCacheAtom(), dispatcher: .shared)

        // Act
        controller.show(prefix: ">", parentWindow: window)

        // Assert
        #expect(controller.state.isVisible)
        #expect(controller.state.rawInput == "> ")
        #expect(controller.state.activeScope == .commands)
    }

    @Test
    func test_show_withPanePrefix_setsPaneScope() {
        let controller = CommandBarPanelController(
            store: WorkspaceStore(), repoCache: RepoCacheAtom(), dispatcher: .shared)

        // Act
        controller.show(prefix: "$", parentWindow: window)

        // Assert
        #expect(controller.state.isVisible)
        #expect(controller.state.rawInput == "$ ")
        #expect(controller.state.activeScope == .panes)
    }

    @Test
    func test_show_publishesCommandBarSurfaceScope() {
        let commandBarSurface = CommandBarSurfaceAtom()
        let workspaceWindowId = UUID()
        let controller = CommandBarPanelController(
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: .shared,
            commandBarSurface: commandBarSurface
        )

        controller.show(prefix: ">", parentWindow: window, workspaceWindowId: workspaceWindowId)

        #expect(commandBarSurface.activeScope == .commands)
        #expect(commandBarSurface.activeScope(for: workspaceWindowId) == .commands)
    }

    @Test
    func test_switchPrefix_updatesCommandBarSurfaceScope() {
        let commandBarSurface = CommandBarSurfaceAtom()
        let workspaceWindowId = UUID()
        let controller = CommandBarPanelController(
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: .shared,
            commandBarSurface: commandBarSurface
        )

        controller.show(prefix: ">", parentWindow: window, workspaceWindowId: workspaceWindowId)
        controller.show(prefix: "$", parentWindow: window, workspaceWindowId: workspaceWindowId)

        #expect(commandBarSurface.activeScope == .panes)
        #expect(commandBarSurface.activeScope(for: workspaceWindowId) == .panes)
    }

    @Test
    func test_show_visibleCommandBar_movesSurfaceToNewWindow() {
        let commandBarSurface = CommandBarSurfaceAtom()
        let firstWindowId = UUID()
        let secondWindowId = UUID()
        let controller = CommandBarPanelController(
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: .shared,
            commandBarSurface: commandBarSurface
        )

        controller.show(prefix: ">", parentWindow: window, workspaceWindowId: firstWindowId)
        controller.show(prefix: "$", parentWindow: window, workspaceWindowId: secondWindowId)

        #expect(commandBarSurface.activeScope(for: firstWindowId) == nil)
        #expect(commandBarSurface.activeScope(for: secondWindowId) == .panes)
    }

    // MARK: - Dismiss via Public API

    @Test
    func test_dismiss_afterShow_resetsState() {
        let controller = CommandBarPanelController(
            store: WorkspaceStore(), repoCache: RepoCacheAtom(), dispatcher: .shared)
        #expect(!controller.state.isVisible)

        // Arrange
        controller.show(parentWindow: window)
        #expect(controller.state.isVisible)

        // Act
        controller.dismiss()

        // Assert
        #expect(!controller.state.isVisible)
        #expect(controller.state.rawInput.isEmpty)
    }

    @Test
    func test_dismiss_clearsCommandBarSurfaceScope() {
        let commandBarSurface = CommandBarSurfaceAtom()
        let workspaceWindowId = UUID()
        let controller = CommandBarPanelController(
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: .shared,
            commandBarSurface: commandBarSurface
        )
        controller.show(parentWindow: window, workspaceWindowId: workspaceWindowId)

        controller.dismiss()

        #expect(commandBarSurface.activeScope == nil)
        #expect(commandBarSurface.activeScope(for: workspaceWindowId) == nil)
    }

    @Test
    func test_dismiss_whenNotVisible_noOp() {
        let controller = CommandBarPanelController(
            store: WorkspaceStore(), repoCache: RepoCacheAtom(), dispatcher: .shared)

        // Arrange — not visible
        #expect(!controller.state.isVisible)

        // Act — should not crash or change state
        controller.dismiss()

        // Assert
        #expect(!controller.state.isVisible)
    }

    // MARK: - Same Scope Behavior (same prefix preserves state)

    @Test
    func test_show_samePrefixTwice_preservesState() {
        let controller = CommandBarPanelController(
            store: WorkspaceStore(), repoCache: RepoCacheAtom(), dispatcher: .shared)

        // Arrange — show with no prefix
        controller.show(parentWindow: window)
        #expect(controller.state.isVisible)
        controller.state.rawInput = "dra"

        // Act — show again with same prefix (nil)
        controller.show(parentWindow: window)

        // Assert — should stay open and preserve state
        #expect(controller.state.isVisible)
        #expect(controller.state.rawInput == "dra")
    }

    @Test
    func test_show_sameCommandPrefixTwice_preservesQueryAndNavigation() {
        let controller = CommandBarPanelController(
            store: WorkspaceStore(), repoCache: RepoCacheAtom(), dispatcher: .shared)

        // Arrange
        controller.show(prefix: ">", parentWindow: window)
        #expect(controller.state.isVisible)
        controller.state.rawInput = "> close"
        controller.state.selectedIndex = 2
        let level = makeCommandBarLevel(id: "close-tab", title: "Close Tab", parentLabel: "Tab")
        controller.state.pushLevel(level)

        // Act
        controller.show(prefix: ">", parentWindow: window)

        // Assert
        #expect(controller.state.isVisible)
        #expect(controller.state.rawInput.isEmpty)
        #expect(controller.state.isNested)
        #expect(controller.state.selectedIndex == 0)
    }

    // MARK: - Switch Behavior (different prefix → switch in-place)

    @Test
    func test_show_differentPrefix_switchesInPlace() {
        let controller = CommandBarPanelController(
            store: WorkspaceStore(), repoCache: RepoCacheAtom(), dispatcher: .shared)

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
        let controller = CommandBarPanelController(
            store: WorkspaceStore(), repoCache: RepoCacheAtom(), dispatcher: .shared)

        // Arrange — open with ">"
        controller.show(prefix: ">", parentWindow: window)
        #expect(controller.state.activeScope == .commands)

        // Act — switch to "$"
        controller.show(prefix: "$", parentWindow: window)

        // Assert
        #expect(controller.state.isVisible)
        #expect(controller.state.rawInput == "$ ")
        #expect(controller.state.activeScope == .panes)
    }

    // MARK: - Full Lifecycle

    @Test
    func test_fullLifecycle_showQueryPushDismiss() {
        let controller = CommandBarPanelController(
            store: WorkspaceStore(), repoCache: RepoCacheAtom(), dispatcher: .shared)

        // Act — show
        controller.show(prefix: ">", parentWindow: window)
        #expect(controller.state.isVisible)

        // Act — simulate user typing a query
        controller.state.rawInput = "> close"
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
        #expect(controller.state.rawInput.isEmpty)
        #expect(controller.state.selectedIndex == 0)
    }
}
