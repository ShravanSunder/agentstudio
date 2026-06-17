import Foundation
import Testing

@testable import AgentStudio

@Suite("InboxNotificationListSection visible notification ids")
struct InboxNotificationVisibleNotificationIdsTests {
    @Test("visible notification ids only include rendered rows")
    func visibleNotificationIdsOnlyIncludeRenderedRows() {
        let matchingId = UUID()
        let matching = Self.makeNotification(
            id: matchingId,
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .approvalRequested,
            title: "Need Review",
            lane: .actionNeeded,
            semantic: .approvalRequested
        )
        let hiddenBySearch = Self.makeNotification(
            timestamp: Date(timeIntervalSince1970: 101),
            kind: .approvalRequested,
            title: "Different",
            lane: .actionNeeded,
            semantic: .approvalRequested
        )
        let hiddenByContentMode = Self.makeNotification(
            timestamp: Date(timeIntervalSince1970: 102),
            kind: .unseenActivity,
            title: "Need Review Activity",
            lane: .activity,
            semantic: .unseenActivity
        )

        let model = InboxNotificationListModel(
            notifications: [matching, hiddenBySearch, hiddenByContentMode],
            grouping: .none,
            sort: .oldestFirst,
            searchText: "review",
            contentMode: .rollUpAlerts,
            rowStateFilter: .unreadOnly
        )

        #expect(model.sections.visibleNotificationIds == [matchingId])
    }

    private static func makeNotification(
        id: UUID = UUID(),
        timestamp: Date,
        kind: InboxNotificationKind,
        title: String,
        lane: InboxNotificationClaimLane,
        semantic: InboxNotificationClaimSemantic
    ) -> InboxNotification {
        InboxNotification(
            id: id,
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
}
