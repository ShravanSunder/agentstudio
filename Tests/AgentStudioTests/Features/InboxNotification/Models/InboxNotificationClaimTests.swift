import Foundation
import Testing

@testable import AgentStudio

@Suite("InboxNotificationClaim")
struct InboxNotificationClaimTests {
    @Test("claim key equality includes session id")
    func claimKeyEqualityIncludesSessionId() {
        let paneId = UUID()
        let sessionId = UUID()
        let matching = InboxNotificationClaimKey(
            paneId: paneId,
            lane: .activity,
            semantic: .unseenActivity,
            sessionId: sessionId
        )
        let same = InboxNotificationClaimKey(
            paneId: paneId,
            lane: .activity,
            semantic: .unseenActivity,
            sessionId: sessionId
        )
        let differentSession = InboxNotificationClaimKey(
            paneId: paneId,
            lane: .activity,
            semantic: .unseenActivity,
            sessionId: UUID()
        )

        #expect(matching == same)
        #expect(matching != differentSession)
    }

    @Test("activity and action-needed lanes can merge within an activity session")
    func activityAndActionNeededLanesCanMergeWithinActivitySession() {
        #expect(InboxNotificationClaimLane.activity.canMergeWithinActivitySession)
        #expect(InboxNotificationClaimLane.actionNeeded.canMergeWithinActivitySession)
        #expect(InboxNotificationClaimLane.safety.canMergeWithinActivitySession == false)
    }

    @Test("claim coalescence predicate follows read and pane-dismiss state matrix")
    func claimCoalescencePredicateFollowsReadAndPaneDismissStateMatrix() {
        for existingIsRead in [false, true] {
            for existingIsDismissed in [false, true] {
                for incomingIsRead in [false, true] {
                    for incomingIsDismissed in [false, true] {
                        let existing = makeNotification(
                            isRead: existingIsRead,
                            isDismissedFromPaneInbox: existingIsDismissed
                        )
                        let incoming = makeNotification(
                            isRead: incomingIsRead,
                            isDismissedFromPaneInbox: incomingIsDismissed
                        )
                        let expected =
                            (!existingIsRead && !existingIsDismissed)
                            || (existingIsRead && existingIsDismissed && incomingIsRead
                                && incomingIsDismissed)

                        #expect(
                            InboxNotificationClaimCoalescence.canCoalesce(
                                existing: existing,
                                incoming: incoming
                            ) == expected
                        )
                    }
                }
            }
        }
    }

    private func makeNotification(
        isRead: Bool,
        isDismissedFromPaneInbox: Bool
    ) -> InboxNotification {
        InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .unseenActivity,
            title: "Activity",
            body: nil,
            source: .pane(.init(paneId: UUID())),
            isRead: isRead,
            isDismissedFromPaneInbox: isDismissedFromPaneInbox
        )
    }
}
