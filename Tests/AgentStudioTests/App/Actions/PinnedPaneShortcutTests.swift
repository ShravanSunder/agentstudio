import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@MainActor
@Suite("Pinned pane shortcut ownership", .serialized)
struct PinnedPaneShortcutTests {
    @Test("pinned arrows share terminal and global routes with stable workspace ownership")
    func pinnedArrowContextsAndOwnership() {
        for shortcut in [AppShortcut.focusPreviousPinnedPane, .focusNextPinnedPane] {
            let arrow: ShortcutArrowKey = shortcut == .focusPreviousPinnedPane ? .up : .down
            let trigger = ShortcutTrigger(key: .arrow(arrow), modifiers: [.option, .shift])
            #expect(ShortcutDecoder.shortcut(for: trigger, in: .global) == shortcut)
            #expect(ShortcutDecoder.shortcut(for: trigger, in: .terminalAppOwned) == shortcut)
            #expect(AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(shortcut, keyboardOwner: .mainWindowChain))
            #expect(!AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(shortcut, keyboardOwner: .managementLayer))
            #expect(!AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(shortcut, keyboardOwner: .sidebar(.panes)))
            #expect(!AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(shortcut, keyboardOwner: .otherWindow))
            #expect(shortcut.command.definition.shortcut == shortcut)
            #expect(!AppShortcutDispatchPolicy.isTerminalRuntimeCommand(shortcut.command))
        }
    }
}
