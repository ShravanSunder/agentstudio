import Foundation
import Testing

@testable import AgentStudio

@Suite("InboxNotificationListModel content mode")
struct InboxNotificationListModelContentModeTests {
    @Test("content mode filters attention activity and all rows")
    func contentModeFiltersAttentionActivityAndAllRows() {
        let activity = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .unseenActivity,
            title: "Activity",
            lane: .activity,
            semantic: .unseenActivity
        )
        let action = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 101),
            kind: .approvalRequested,
            title: "Action",
            lane: .actionNeeded,
            semantic: .approvalRequested
        )
        let settled = makeInboxNotification(
            timestamp: Date(timeIntervalSince1970: 102),
            kind: .agentSettledActivity,
            title: "Settled",
            lane: .settledAgent,
            semantic: .agentSettled
        )

        let notifications = [activity, action, settled]
        let rollUpModel = makeModel(notifications: notifications, contentMode: .rollUpAlerts)
        let activityModel = makeModel(notifications: notifications, contentMode: .activity)
        let allModel = makeModel(notifications: notifications, contentMode: .all)

        #expect(titles(in: rollUpModel) == ["Action", "Settled"])
        #expect(titles(in: activityModel) == ["Activity"])
        #expect(titles(in: allModel) == ["Activity", "Action", "Settled"])
    }

    private func makeInboxNotification(
        timestamp: Date,
        kind: InboxNotificationKind,
        title: String,
        lane: InboxNotificationClaimLane,
        semantic: InboxNotificationClaimSemantic
    ) -> InboxNotification {
        InboxNotification(
            id: UUID(),
            timestamp: timestamp,
            kind: kind,
            title: title,
            body: nil,
            source: .global,
            claimKey: .init(
                paneId: UUID(),
                lane: lane,
                semantic: semantic,
                sessionId: nil
            ),
            isRead: false,
            isDismissedFromPaneInbox: false
        )
    }

    private func makeModel(
        notifications: [InboxNotification],
        contentMode: InboxNotificationContentMode
    ) -> InboxNotificationListModel {
        InboxNotificationListModel(
            notifications: notifications,
            grouping: .none,
            sort: .oldestFirst,
            searchText: "",
            contentMode: contentMode
        )
    }

    private func titles(in model: InboxNotificationListModel) -> [String] {
        model.sections.flatMap { $0.notifications }.map { $0.title }
    }
}
