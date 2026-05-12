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

}
