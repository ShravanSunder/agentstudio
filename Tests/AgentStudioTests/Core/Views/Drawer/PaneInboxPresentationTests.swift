import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite("PaneInboxPresentation")
struct PaneInboxPresentationTests {
    @Test("trailing actions inject pane inbox unread count and preserve existing actions")
    func trailingActionsInjectUnreadCount() {
        let parentPaneId = UUID()
        let drawerChildPaneId = UUID()
        let paneIds = [parentPaneId, drawerChildPaneId]
        var openedParentPaneId: UUID?
        var openedPaneIds: [UUID]?
        var didOpenFinder = false
        let baseActions = DrawerOverlay.TrailingActions(
            canOpenTarget: true,
            editorMenuContent: AnyView(EmptyView()),
            editorMenuPresented: .constant(false),
            buttonTitle: "Cursor",
            onOpenFinder: { didOpenFinder = true }
        )
        let presentation = PaneInboxPresentation(
            unreadCount: { requestedPaneIds in requestedPaneIds == paneIds ? 1 : 0 },
            open: { _, _ in },
            toggle: { parentPaneId, paneIds in
                openedParentPaneId = parentPaneId
                openedPaneIds = paneIds
            },
            pendingRequest: { nil },
            clearRequest: { _ in },
            popoverContent: { _, _ in AnyView(EmptyView()) }
        )
        var isPopoverPresented = false

        let actions = presentation.trailingActions(
            parentPaneId: parentPaneId,
            paneIds: paneIds,
            baseTrailingActions: baseActions,
            inboxPopoverPresented: Binding(
                get: { isPopoverPresented },
                set: { isPopoverPresented = $0 }
            )
        )

        #expect(actions.canOpenTarget == true)
        #expect(actions.buttonTitle == "Cursor")
        #expect(actions.inboxUnreadCount == 1)
        #expect(actions.inboxPopoverContent != nil)

        actions.inboxPopoverPresented.wrappedValue = true
        #expect(isPopoverPresented)

        actions.onOpenFinder()
        #expect(didOpenFinder)

        actions.onOpenInbox?()
        #expect(openedParentPaneId == parentPaneId)
        #expect(openedPaneIds == paneIds)
    }
}
