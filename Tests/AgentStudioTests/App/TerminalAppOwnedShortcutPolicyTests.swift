import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Terminal app-owned shortcut policy")
struct TerminalAppOwnedShortcutPolicyTests {
    @Test("terminal app-owned shortcuts are blocked by transient surfaces")
    func terminalAppOwnedShortcutsAreBlockedByTransientSurfaces() {
        let context = KeyboardRoutingContext(
            stableOwner: .mainWindowChain,
            activeSurface: .transient(.paneInbox(parentPaneId: UUID())),
            workspaceWindowId: UUID()
        )

        #expect(!AppShortcutDispatchPolicy.shouldDispatchTerminalAppOwnedShortcut(.nextTab, context: context))
        #expect(!AppShortcutDispatchPolicy.shouldDispatchTerminalAppOwnedShortcut(.scrollToBottom, context: context))
    }

    @Test("command bar activation is allowed through terminal transient surfaces")
    func commandBarActivationIsAllowedThroughTerminalTransientSurfaces() {
        let context = KeyboardRoutingContext(
            stableOwner: .mainWindowChain,
            activeSurface: .transient(.editorChooser(paneId: UUID())),
            workspaceWindowId: UUID()
        )

        #expect(AppShortcut.newTab.spec.contexts.contains(.terminalAppOwned))
        #expect(AppShortcut.newTab.command == .showCommandBarRepos)
        #expect(
            AppShortcutDispatchPolicy.shouldDispatchTerminalAppOwnedShortcut(
                .showCommandBarEverything, context: context))
        #expect(AppShortcutDispatchPolicy.shouldDispatchTerminalAppOwnedShortcut(.newTab, context: context))
    }

    @Test("terminal app-owned shortcuts are blocked when command bar owns keyboard")
    func terminalAppOwnedShortcutsAreBlockedWhenCommandBarOwnsKeyboard() {
        let context = KeyboardRoutingContext(
            stableOwner: .mainWindowChain,
            activeSurface: .commandBar(scope: .everything),
            workspaceWindowId: UUID()
        )

        #expect(!AppShortcutDispatchPolicy.shouldDispatchTerminalAppOwnedShortcut(.nextTab, context: context))
        #expect(
            AppShortcutDispatchPolicy.shouldDispatchTerminalAppOwnedShortcut(
                .showCommandBarEverything, context: context))
    }
}
