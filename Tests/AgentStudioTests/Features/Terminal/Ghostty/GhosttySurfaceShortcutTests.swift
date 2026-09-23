import AgentStudioInfrastructure
import AgentStudioTestSupport
import AppKit
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioTerminal

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
    func test_appOwnedShortcuts_containsCmdTQuickOpen() {
        #expect(
            Ghostty.SurfaceView.appOwnedShortcuts.contains(.newTab),
            "Expected Quick Open in appOwnedShortcuts"
        )
        #expect(AppShortcut.newTab.command == .showCommandBarQuickOpen)
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
    func test_appOwnedShortcuts_containsCommandOptionKScrollToBottom() {
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

    @Test(arguments: terminalNavigationShortcuts)
    func terminalAppOwnedShortcutHandler_swallowsRejectedShortcutWithoutDispatch(shortcut: AppShortcut) {
        withTestCoreAtoms { atoms in
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
                uiState: atoms.workspaceSidebarState,
                commandBarSurface: atoms.commandBarSurface,
                transientKeyboardSurface: atoms.transientKeyboardSurface
            )

            let result = Ghostty.SurfaceView.handleTerminalAppOwnedShortcut(
                trigger: shortcut.trigger,
                context: context,
                canDispatch: { command, _ in command == shortcut.command },
                dispatch: { command, _ in dispatchedCommands.append(command) }
            )

            #expect(result == .swallowed)
            #expect(dispatchedCommands.isEmpty)
        }
    }

    @Test(arguments: terminalNavigationShortcuts, [false, true])
    func terminalAppOwnedShortcutHandler_targetsSourcePaneForTerminalRuntimeCommands(
        shortcut: AppShortcut, managementIsActive: Bool
    ) {
        withTestCoreAtoms { atoms in
            let windowId = UUIDv7.generate()
            let sourcePaneId = UUIDv7.generate()
            var dispatches: [(command: AppCommand, paneId: UUID?)] = []
            atoms.windowLifecycle.recordWindowRegistered(windowId)
            atoms.windowLifecycle.recordWindowBecameKey(windowId)
            if managementIsActive { atoms.managementLayer.activate() }

            let context = KeyboardRoutingContext.current(
                windowLifecycle: atoms.windowLifecycle,
                managementLayer: atoms.managementLayer,
                uiState: atoms.workspaceSidebarState,
                commandBarSurface: atoms.commandBarSurface,
                transientKeyboardSurface: atoms.transientKeyboardSurface
            )

            let result = Ghostty.SurfaceView.handleTerminalAppOwnedShortcut(
                trigger: shortcut.trigger,
                context: context,
                sourcePaneId: sourcePaneId,
                canDispatch: { command, paneId in
                    command == shortcut.command && paneId == sourcePaneId
                },
                dispatch: { command, paneId in
                    dispatches.append((command, paneId))
                }
            )

            #expect(result == .dispatched(shortcut.command))
            #expect(dispatches.count == 1)
            #expect(dispatches.first?.command == shortcut.command)
            #expect(dispatches.first?.paneId == sourcePaneId)
        }
    }

    @Test(arguments: [false, true])
    func terminalAppOwnedShortcutHandler_doesNotTargetCommandBarShortcutsToSourcePane(hasSource: Bool) {
        withTestCoreAtoms { atoms in
            let windowId = UUID()
            let sourcePaneId = hasSource ? UUIDv7.generate() : nil
            var dispatches: [(command: AppCommand, paneId: UUID?)] = []
            atoms.windowLifecycle.recordWindowRegistered(windowId)
            atoms.windowLifecycle.recordWindowBecameKey(windowId)

            let context = KeyboardRoutingContext.current(
                windowLifecycle: atoms.windowLifecycle,
                managementLayer: atoms.managementLayer,
                uiState: atoms.workspaceSidebarState,
                commandBarSurface: atoms.commandBarSurface,
                transientKeyboardSurface: atoms.transientKeyboardSurface
            )

            let result = Ghostty.SurfaceView.handleTerminalAppOwnedShortcut(
                trigger: .init(key: .character(.p), modifiers: [.command]),
                context: context,
                sourcePaneId: sourcePaneId,
                canDispatch: { command, paneId in
                    command == .showCommandBarEverything && paneId == nil
                },
                dispatch: { command, paneId in
                    dispatches.append((command, paneId))
                }
            )

            #expect(result == .dispatched(.showCommandBarEverything))
            #expect(dispatches.count == 1)
            #expect(dispatches.first?.command == .showCommandBarEverything)
            #expect(dispatches.first?.paneId == nil)
        }
    }

    @Test(arguments: terminalNavigationShortcuts)
    func rejectedTerminalSourceDoesNotFallBackToAnotherPane(shortcut: AppShortcut) {
        withTestCoreAtoms { atoms in
            let windowId = UUIDv7.generate()
            let rejectedPaneId = UUIDv7.generate()
            atoms.windowLifecycle.recordWindowRegistered(windowId)
            atoms.windowLifecycle.recordWindowBecameKey(windowId)
            let context = KeyboardRoutingContext.current(
                windowLifecycle: atoms.windowLifecycle,
                managementLayer: atoms.managementLayer,
                uiState: atoms.workspaceSidebarState,
                commandBarSurface: atoms.commandBarSurface,
                transientKeyboardSurface: atoms.transientKeyboardSurface
            )
            var requestedTargets: [UUID?] = []
            var dispatchedCommands: [AppCommand] = []

            let result = Ghostty.SurfaceView.handleTerminalAppOwnedShortcut(
                trigger: shortcut.trigger, context: context, sourcePaneId: rejectedPaneId,
                canDispatch: { _, paneId in
                    requestedTargets.append(paneId)
                    return false
                },
                dispatch: { command, _ in dispatchedCommands.append(command) }
            )

            #expect(result == .swallowed)
            #expect(requestedTargets == [rejectedPaneId])
            #expect(dispatchedCommands.isEmpty)
        }
    }

    @Test(arguments: terminalNavigationShortcuts)
    func missingTerminalSourceDoesNotUseContextualFallback(shortcut: AppShortcut) {
        withTestCoreAtoms { atoms in
            let windowId = UUIDv7.generate()
            atoms.windowLifecycle.recordWindowRegistered(windowId)
            atoms.windowLifecycle.recordWindowBecameKey(windowId)
            let context = KeyboardRoutingContext.current(
                windowLifecycle: atoms.windowLifecycle,
                managementLayer: atoms.managementLayer,
                uiState: atoms.workspaceSidebarState,
                commandBarSurface: atoms.commandBarSurface,
                transientKeyboardSurface: atoms.transientKeyboardSurface
            )
            var attemptedContextualDispatch = false
            var dispatchedCommands: [AppCommand] = []

            let result = Ghostty.SurfaceView.handleTerminalAppOwnedShortcut(
                trigger: shortcut.trigger, context: context, sourcePaneId: nil,
                canDispatch: { _, _ in
                    attemptedContextualDispatch = true
                    return true
                },
                dispatch: { command, _ in dispatchedCommands.append(command) }
            )

            #expect(result == .swallowed)
            #expect(!attemptedContextualDispatch)
            #expect(dispatchedCommands.isEmpty)
        }
    }

    @Test
    func appOwnedTerminalShortcuts_includeScrollAndPromptNavigation() {
        #expect(Ghostty.SurfaceView.appOwnedShortcuts.contains(.scrollToBottom))
        #expect(Ghostty.SurfaceView.appOwnedShortcuts.contains(.scrollPageUp))
        #expect(Ghostty.SurfaceView.appOwnedShortcuts.contains(.scrollPageDown))
        #expect(Ghostty.SurfaceView.appOwnedShortcuts.contains(.scrollSmallStepUp))
        #expect(Ghostty.SurfaceView.appOwnedShortcuts.contains(.scrollSmallStepDown))
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
    func test_appOwnedShortcuts_reserveInboxAndSidebarCommandsFromTerminal() {
        #expect(
            Ghostty.SurfaceView.appOwnedShortcuts.contains(.showInboxNotifications),
            "Retired sidebar Inbox trigger remains reserved from terminal input"
        )
        #expect(
            Ghostty.SurfaceView.appOwnedShortcuts.contains(.showPaneInboxNotifications),
            "Retired pane Inbox trigger remains reserved from terminal input"
        )
        #expect(Ghostty.SurfaceView.appOwnedShortcuts.contains(.toggleSidebar))
        #expect(Ghostty.SurfaceView.appOwnedShortcuts.contains(.focusSidebar))
        #expect(!Ghostty.SurfaceView.appOwnedShortcuts.contains(.showReposSidebar))
    }
}

private let terminalNavigationShortcuts: [AppShortcut] = [
    .scrollToBottom, .scrollPageUp, .scrollPageDown, .scrollSmallStepUp,
    .scrollSmallStepDown, .jumpToPreviousPrompt, .jumpToNextPrompt,
]
