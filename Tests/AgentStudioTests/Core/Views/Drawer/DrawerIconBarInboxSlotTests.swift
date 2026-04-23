import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite("DrawerIconBar inbox slot")
struct DrawerIconBarInboxSlotTests {
    @Test("trailing actions carry optional inbox callback and unread count")
    func trailingActionsCarryInboxConfiguration() {
        var didOpenInbox = false
        let actions = makeTrailingActions(
            inboxUnreadCount: 3,
            onOpenInbox: {
                didOpenInbox = true
            }
        )

        #expect(actions.inboxUnreadCount == 3)
        actions.onOpenInbox?()
        #expect(didOpenInbox)
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
            inboxUnreadCount: inboxUnreadCount
        )
    }
}
