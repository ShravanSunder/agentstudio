import AppKit
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
final class GhosttySurfaceShortcutTests {

    // MARK: - App-Owned Shortcut List

    @Test
    func test_appOwnedShortcuts_containsAtLeast3() {
        // Assert — command bar shortcuts, drawer-pane creation, and terminal navigation are registered
        #expect(
            Ghostty.SurfaceView.appOwnedShortcuts.count >= 5,
            "Expected app-owned shortcuts to include ⌘P, ⌘⇧P, ⌘⌥P, ⌘⇧D, and terminal navigation"
        )
    }

    @Test
    func test_appOwnedShortcuts_containsCmdP() {
        // Assert
        #expect(
            Ghostty.SurfaceView.appOwnedShortcuts.contains(.showCommandBarEverything),
            "Expected quick open in appOwnedShortcuts"
        )
    }

    @Test
    func test_appOwnedShortcuts_containsCmdTRepoCommandBar() {
        #expect(
            Ghostty.SurfaceView.appOwnedShortcuts.contains(.newTab),
            "Expected repo command bar in appOwnedShortcuts"
        )
        #expect(AppShortcut.newTab.command == .showCommandBarRepos)
    }

    @Test
    func test_appOwnedShortcuts_containsCmdShiftP() {
        // Assert
        #expect(
            Ghostty.SurfaceView.appOwnedShortcuts.contains(.showCommandBarCommands),
            "Expected command palette in appOwnedShortcuts"
        )
    }

    @Test
    func test_appOwnedShortcuts_containsCmdOptionP() {
        // Assert
        #expect(
            Ghostty.SurfaceView.appOwnedShortcuts.contains(.showCommandBarPanes),
            "Expected pane picker in appOwnedShortcuts"
        )
    }

    @Test
    func test_appOwnedShortcuts_containsCmdShiftD() {
        // Assert
        #expect(
            Ghostty.SurfaceView.appOwnedShortcuts.contains(.addDrawerPane),
            "Expected add drawer pane in appOwnedShortcuts"
        )
    }

    @Test
    func test_appOwnedShortcuts_containsCmdShiftKScrollToBottom() {
        #expect(
            Ghostty.SurfaceView.appOwnedShortcuts.contains(.scrollToBottom),
            "Expected scroll-to-bottom in appOwnedShortcuts"
        )
    }

    @Test
    func terminalHostSuppressedTriggers_swallowCmdKClearScrollback() {
        let trigger = ShortcutTrigger(key: .character(.k), modifiers: [.command])

        #expect(Ghostty.SurfaceView.shouldSuppressTerminalHostTrigger(trigger))
    }

    @Test
    func terminalAppOwnedShortcutHandler_swallowsRejectedShortcutWithoutDispatch() async throws {
        try await withIsolatedCommandDispatcher(
            configure: {},
            body: {
                withTestAtomRegistry { atoms in
                    let windowId = UUID()
                    let tabId = UUID()
                    var dispatchedCommands: [AppCommand] = []
                    atoms.windowLifecycle.recordWindowRegistered(windowId)
                    atoms.windowLifecycle.recordWindowBecameKey(windowId)
                    _ = atoms.transientKeyboardSurface.present(
                        .arrangementPanel(tabId: tabId),
                        workspaceWindowId: windowId
                    )

                    let context = KeyboardRoutingContext.current(
                        windowLifecycle: atoms.windowLifecycle,
                        managementLayer: atoms.managementLayer,
                        uiState: atoms.uiState,
                        commandBarSurface: atoms.commandBarSurface,
                        transientKeyboardSurface: atoms.transientKeyboardSurface
                    )

                    let result = Ghostty.SurfaceView.handleTerminalAppOwnedShortcut(
                        trigger: .init(key: .character(.k), modifiers: [.command, .shift]),
                        context: context,
                        canDispatch: { _ in true },
                        dispatch: { dispatchedCommands.append($0) }
                    )

                    #expect(result == .swallowed)
                    #expect(dispatchedCommands.isEmpty)
                }
            })
    }

    @Test
    func appOwnedTerminalShortcuts_includeScrollAndPromptNavigation() {
        #expect(Ghostty.SurfaceView.appOwnedShortcuts.contains(.scrollToBottom))
        #expect(Ghostty.SurfaceView.appOwnedShortcuts.contains(.scrollPageUp))
        #expect(Ghostty.SurfaceView.appOwnedShortcuts.contains(.jumpToPreviousPrompt))
        #expect(Ghostty.SurfaceView.appOwnedShortcuts.contains(.jumpToNextPrompt))
    }

    @Test
    func appOwnedTerminalShortcuts_includeTabAndPaneOrdinals() {
        #expect(Ghostty.SurfaceView.appOwnedShortcuts.contains(.selectTab1))
        #expect(Ghostty.SurfaceView.appOwnedShortcuts.contains(.selectTab9))
        #expect(Ghostty.SurfaceView.appOwnedShortcuts.contains(.focusPane1))
        #expect(Ghostty.SurfaceView.appOwnedShortcuts.contains(.focusPane9))
    }

    @Test
    func test_appOwnedShortcuts_containsSidebarAndPaneInboxShortcuts() {
        #expect(
            Ghostty.SurfaceView.appOwnedShortcuts.contains(.showInboxNotifications),
            "Expected sidebar inbox shortcut in appOwnedShortcuts"
        )
        #expect(
            Ghostty.SurfaceView.appOwnedShortcuts.contains(.showPaneInboxNotifications),
            "Expected pane inbox shortcut in appOwnedShortcuts"
        )
        #expect(
            Ghostty.SurfaceView.appOwnedShortcuts.contains(.showWorktreeSidebar),
            "Expected worktree sidebar shortcut in appOwnedShortcuts"
        )
    }
}
