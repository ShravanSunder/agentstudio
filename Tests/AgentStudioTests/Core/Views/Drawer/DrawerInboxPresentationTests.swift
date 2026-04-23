import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite("DrawerInboxPresentation")
struct DrawerInboxPresentationTests {
    @Test("trailing actions inject drawer unread count and preserve existing actions")
    func trailingActionsInjectUnreadCount() {
        let drawerPaneId = UUID()
        var openedPaneIds: [UUID]?
        var didOpenFinder = false
        let baseActions = DrawerOverlay.TrailingActions(
            canOpenTarget: true,
            editorMenuContent: AnyView(EmptyView()),
            editorMenuPresented: .constant(false),
            buttonTitle: "Cursor",
            onOpenFinder: { didOpenFinder = true }
        )
        let presentation = DrawerInboxPresentation(
            unreadCount: { paneIds in paneIds == [drawerPaneId] ? 1 : 0 },
            open: { openedPaneIds = $0 },
            pendingRequest: { nil },
            clearRequest: { _ in },
            popoverContent: { _, _ in AnyView(EmptyView()) }
        )

        let actions = presentation.trailingActions(
            drawerPaneIds: [drawerPaneId],
            baseTrailingActions: baseActions
        )

        #expect(actions.canOpenTarget == true)
        #expect(actions.buttonTitle == "Cursor")
        #expect(actions.inboxUnreadCount == 1)

        actions.onOpenFinder()
        #expect(didOpenFinder)

        actions.onOpenInbox?()
        #expect(openedPaneIds == [drawerPaneId])
    }
}
