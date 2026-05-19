import AppKit
import Testing

@testable import AgentStudio

@MainActor
@Suite("PaneTabViewController global shortcut routing")
struct PaneTabViewControllerGlobalShortcutRoutingTests {
    @Test("filterSidebar is only handled when the repos sidebar owns focus")
    func filterSidebarRequiresFocusedReposSidebar() {
        #expect(
            !AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                .filterSidebar,
                keyboardOwner: .mainWindowChain
            )
        )

        #expect(
            !AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                .filterSidebar,
                keyboardOwner: .sidebar(.inbox)
            )
        )

        #expect(
            AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                .filterSidebar,
                keyboardOwner: .sidebar(.repos)
            )
        )

        #expect(
            !AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                .filterSidebar,
                keyboardOwner: .managementLayer
            )
        )
    }

    @Test("surface switch shortcuts remain globally routable")
    func surfaceSwitchShortcutsRemainGlobal() {
        #expect(
            AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                .showInboxNotifications,
                keyboardOwner: .sidebar(.inbox)
            )
        )
        #expect(
            AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                .showWorktreeSidebar,
                keyboardOwner: .sidebar(.repos)
            )
        )
    }

    @Test("sidebar focus blocks workspace global shortcuts")
    func sidebarFocusBlocksWorkspaceGlobalShortcuts() {
        for shortcut in [AppShortcut.nextTab, .prevTab, .addDrawerPane, .showPaneInboxNotifications] {
            #expect(
                !AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                    shortcut,
                    keyboardOwner: .sidebar(.inbox)
                ),
                "\(shortcut) should not dispatch while inbox owns keyboard focus"
            )
        }
    }

    @Test("production global key path consults keyboard owner policy")
    func productionGlobalKeyPathConsultsKeyboardOwnerPolicy() async throws {
        let harness = makeHarness()
        let handler = MockCommandHandler()
        let windowId = UUID()
        atom(\.windowLifecycle).recordWindowRegistered(windowId)
        atom(\.windowLifecycle).recordWindowBecameKey(windowId)
        atom(\.uiState).setSidebarCollapsed(false)
        atom(\.uiState).setSidebarSurface(.inbox)
        atom(\.uiState).setSidebarHasFocus(true)

        let event = try #require(
            makeKeyEvent(
                modifierFlags: [.command, .option],
                characters: "l",
                charactersIgnoringModifiers: "l",
                keyCode: 37
            )
        )
        let trigger = try #require(ShortcutDecoder.decode(event: event))
        #expect(ShortcutDecoder.shortcut(for: trigger, in: .global) == .nextTab)

        try await withIsolatedCommandDispatcher(
            configure: {
                CommandDispatcher.shared.handler = handler
                CommandDispatcher.shared.appCommandRouter = nil
            },
            body: {
                #expect(!harness.controller.handleAppOwnedKeyEvent(event))
                #expect(handler.executedCommands.isEmpty)
            }
        )
    }

    @Test("old tab cycling shortcut is not decoded after migration")
    func oldTabCyclingShortcutIsNotDecodedAfterMigration() {
        let oldNextTabTrigger = ShortcutTrigger(key: .character(.rightBracket), modifiers: [.command, .shift])
        let oldPrevTabTrigger = ShortcutTrigger(key: .character(.leftBracket), modifiers: [.command, .shift])

        #expect(ShortcutDecoder.shortcut(for: oldNextTabTrigger, in: .global) == nil)
        #expect(ShortcutDecoder.shortcut(for: oldPrevTabTrigger, in: .global) == nil)
    }

    @Test("management layer preserves command-modified pass through")
    func managementLayerPreservesCommandModifiedPassThrough() {
        #expect(
            AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                .showPaneInboxNotifications,
                keyboardOwner: .managementLayer
            )
        )
    }
}
