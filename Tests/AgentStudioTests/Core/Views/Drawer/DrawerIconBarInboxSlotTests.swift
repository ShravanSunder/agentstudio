import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite("DrawerIconBar inbox slot")
struct DrawerIconBarInboxSlotTests {
    @Test("trailing actions carry optional inbox callback and unread badge")
    func trailingActionsCarryInboxConfiguration() {
        var didOpenInbox = false
        let actions = makeTrailingActions(
            inboxUnreadCount: 3,
            onOpenInbox: {
                didOpenInbox = true
            }
        )

        #expect(actions.inboxUnreadBadge?.text == "3")
        #expect(actions.inboxPopoverContent == nil)
        actions.onOpenInbox?()
        #expect(didOpenInbox)
    }

    @Test("pane inbox unread badge uses compact overflow text")
    func paneInboxUnreadBadgeUsesCompactOverflowText() {
        #expect(PaneInboxUnreadBadge(unreadCount: AppPolicies.PaneInbox.unreadBadgeDisplayLimit)?.text == "9")
        #expect(PaneInboxUnreadBadge(unreadCount: 10)?.text == "9+")
    }

    @Test("icon bar accepts trailing inbox action configuration")
    func iconBarAcceptsInboxConfiguration() {
        let actions = makeTrailingActions(inboxUnreadCount: 2, onOpenInbox: {})

        let view = DrawerIconBar(
            isExpanded: false,
            onAdd: {},
            onToggleExpand: {},
            trailingActions: actions
        )

        _ = view.body
    }

    @Test("empty drawer add tooltip uses empty drawer shortcut")
    func emptyDrawerAddTooltipUsesEmptyDrawerShortcut() throws {
        let tooltipValue = EmptyDrawerBar.addTooltipValue()
        let emptyDrawerShortcut = try #require(AppShortcut.addDrawerPane.displayKeyBinding(in: .emptyDrawer))

        #expect(tooltipValue.shortcutDisplayText == ShortcutDisplayText(value: emptyDrawerShortcut.displayString))
        #expect(tooltipValue.text == "Add Drawer Pane (\(emptyDrawerShortcut.displayString))")
    }

    private func makeTrailingActions(
        inboxUnreadCount: Int,
        onOpenInbox: (() -> Void)?
    ) -> DrawerOverlay.TrailingActions {
        DrawerOverlay.TrailingActions(
            canOpenTarget: true,
            editorMenuContent: AnyView(EmptyView()),
            editorMenuPresented: .constant(false),
            buttonTitle: "Cursor",
            onOpenFinder: {},
            onOpenInbox: onOpenInbox,
            inboxUnreadBadge: PaneInboxUnreadBadge(unreadCount: inboxUnreadCount)
        )
    }
}
