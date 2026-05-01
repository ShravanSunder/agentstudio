import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("PaneInboxNotificationPopover")
struct PaneInboxNotificationPopoverTests {
    @Test("popover filters to pane-scope notifications not dismissed from pane inbox")
    func popoverFiltersRelevantNotifications() {
        let parentPaneId = UUID()
        let drawerChildPaneId = UUID()
        let parentVisible = makeNotification(paneId: parentPaneId, title: "Parent")
        let childVisible = makeNotification(paneId: drawerChildPaneId, title: "Child")
        let dismissed = makeNotification(
            paneId: drawerChildPaneId,
            title: "Dismissed",
            isDismissedFromPaneInbox: true
        )
        let unrelated = makeNotification(paneId: UUID(), title: "Other")

        let relevant = PaneInboxNotificationPopover.relevantNotifications(
            paneIds: [parentPaneId, drawerChildPaneId],
            notifications: [dismissed, unrelated, parentVisible, childVisible]
        )

        #expect(relevant.map(\.title) == ["Parent", "Child"])
    }

    @Test("keyboardItems maps relevant notifications to selectable popover items")
    func keyboardItemsForRelevantNotifications() {
        let paneId = UUID()
        let first = makeNotification(id: UUID(), paneId: paneId, title: "First")
        let second = makeNotification(id: UUID(), paneId: paneId, title: "Second")

        let keyboardItems = PaneInboxNotificationPopover.keyboardItems(
            for: [first, second]
        )

        #expect(keyboardItems.map(\.id) == [first.id, second.id])
        #expect(keyboardItems.map(\.shortcutNumber) == [1, 2])
        #expect(keyboardItems.allSatisfy { !$0.supportsAuxiliaryAction })
    }

    @Test("keyboardItems caps numbered shortcuts at selectable popover policy")
    func keyboardItemsCapsNumberedShortcutsAtPolicyLimit() {
        let paneId = UUID()
        let notifications = (0..<(AppPolicies.SelectablePopover.maxNumberedShortcuts + 3)).map { index in
            makeNotification(id: UUID(), paneId: paneId, title: "Notification \(index)")
        }

        let keyboardItems = PaneInboxNotificationPopover.keyboardItems(for: notifications)

        #expect(keyboardItems.count == AppPolicies.SelectablePopover.maxNumberedShortcuts)
        #expect(keyboardItems.map(\.shortcutNumber) == Array(1...AppPolicies.SelectablePopover.maxNumberedShortcuts))
    }

    private func makeNotification(
        id: UUID = UUID(),
        paneId: UUID?,
        title: String = "Notification",
        isDismissedFromPaneInbox: Bool = false
    ) -> InboxNotification {
        InboxNotification(
            id: id,
            timestamp: Date(timeIntervalSince1970: isDismissedFromPaneInbox ? 50 : 100),
            kind: .agentRpc,
            title: title,
            body: nil,
            source: paneId.map { .pane(.init(paneId: $0)) } ?? .global,
            isRead: false,
            isDismissedFromPaneInbox: isDismissedFromPaneInbox
        )
    }
}
