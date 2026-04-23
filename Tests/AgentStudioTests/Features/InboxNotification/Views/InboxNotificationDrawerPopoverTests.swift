import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotificationDrawerPopover")
struct InboxNotificationDrawerPopoverTests {
    @Test("popover filters to drawer pane notifications not dismissed from drawer")
    func popoverFiltersRelevantNotifications() {
        let drawerPaneId = UUID()
        let visible = makeNotification(paneId: drawerPaneId, title: "Visible")
        let dismissed = makeNotification(
            paneId: drawerPaneId,
            title: "Dismissed",
            isDismissedFromDrawer: true
        )
        let unrelated = makeNotification(paneId: UUID(), title: "Other")

        let relevant = InboxNotificationDrawerPopover.relevantNotifications(
            drawerPaneIds: [drawerPaneId],
            notifications: [dismissed, unrelated, visible]
        )

        #expect(relevant.map(\.title) == ["Visible"])
    }

    private func makeNotification(
        paneId: UUID?,
        title: String = "Notification",
        isDismissedFromDrawer: Bool = false
    ) -> InboxNotification {
        InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: isDismissedFromDrawer ? 50 : 100),
            kind: .agentRpc,
            title: title,
            body: nil,
            source: paneId.map { .pane(.init(paneId: $0)) } ?? .global,
            isRead: false,
            isDismissedFromDrawer: isDismissedFromDrawer
        )
    }
}
