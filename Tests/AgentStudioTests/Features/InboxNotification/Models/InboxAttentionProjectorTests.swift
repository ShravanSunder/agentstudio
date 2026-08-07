import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioInboxNotification

@MainActor
@Suite("InboxAttentionProjector")
struct InboxAttentionProjectorTests {
    @Test("projects only unread non-activity notifications for matching panes")
    func projectsOnlyContributingNotificationsForMatchingPanes() throws {
        let actionPaneId = uuid("30000000-0000-7000-8000-000000000001")
        let safetyPaneId = uuid("30000000-0000-7000-8000-000000000002")
        let settledPaneId = uuid("30000000-0000-7000-8000-000000000003")
        let activityPaneId = uuid("30000000-0000-7000-8000-000000000004")
        let unmatchedPaneId = uuid("30000000-0000-7000-8000-000000000005")
        let atom = InboxNotificationAtom()
        atom.replaceAll([
            notification(paneId: actionPaneId, lane: .actionNeeded),
            notification(paneId: safetyPaneId, lane: .safety),
            notification(paneId: settledPaneId, lane: .settledAgent),
            notification(paneId: activityPaneId, lane: .activity),
        ])
        let groups = [
            "action": Set([actionPaneId]),
            "safety": Set([safetyPaneId]),
            "settled": Set([settledPaneId]),
            "activity": Set([activityPaneId]),
            "unmatched": Set([unmatchedPaneId]),
        ]

        let projection = try InboxAttentionProjector.project(
            snapshot: atom.captureAttentionFacts(),
            groups: groups,
            cancellationCheck: {}
        )

        #expect(
            projection == [
                "action": .actionNeeded,
                "safety": .safety,
                "settled": .settledAgent,
            ])
        for (groupId, paneIds) in groups {
            #expect(projection[groupId] == atom.attentionLane(forPaneIds: Array(paneIds)))
        }
    }

    @Test("read notifications do not contribute while dismissed unread notifications still contribute")
    func preservesReadAndDismissedAttentionSemantics() throws {
        let readPaneId = uuid("30000000-0000-7000-8000-000000000011")
        let dismissedPaneId = uuid("30000000-0000-7000-8000-000000000012")
        let atom = InboxNotificationAtom()
        atom.replaceAll([
            notification(paneId: readPaneId, lane: .actionNeeded, isRead: true),
            notification(
                paneId: dismissedPaneId,
                lane: .safety,
                isDismissedFromPaneInbox: true
            ),
        ])
        let groups = [
            "read": Set([readPaneId]),
            "dismissed": Set([dismissedPaneId]),
        ]

        let projection = try InboxAttentionProjector.project(
            snapshot: atom.captureAttentionFacts(),
            groups: groups,
            cancellationCheck: {}
        )

        #expect(projection == ["dismissed": .safety])
        for (groupId, paneIds) in groups {
            #expect(projection[groupId] == atom.attentionLane(forPaneIds: Array(paneIds)))
        }
    }

    @Test("projects attention independently for mixed pane groups")
    func projectsMixedGroupsIndependently() throws {
        let firstPaneId = uuid("30000000-0000-7000-8000-000000000021")
        let secondPaneId = uuid("30000000-0000-7000-8000-000000000022")
        let thirdPaneId = uuid("30000000-0000-7000-8000-000000000023")
        let atom = InboxNotificationAtom()
        atom.replaceAll([
            notification(paneId: firstPaneId, lane: .settledAgent),
            notification(paneId: secondPaneId, lane: .safety),
            notification(paneId: thirdPaneId, lane: .activity),
        ])
        let groups = [
            "first-and-third": Set([firstPaneId, thirdPaneId]),
            "second-and-third": Set([secondPaneId, thirdPaneId]),
            "all": Set([firstPaneId, secondPaneId, thirdPaneId]),
        ]

        let projection = try InboxAttentionProjector.project(
            snapshot: atom.captureAttentionFacts(),
            groups: groups,
            cancellationCheck: {}
        )

        #expect(
            projection == [
                "first-and-third": .settledAgent,
                "second-and-third": .safety,
                "all": .safety,
            ])
        for (groupId, paneIds) in groups {
            #expect(projection[groupId] == atom.attentionLane(forPaneIds: Array(paneIds)))
        }
    }

    @Test("action needed takes precedence over safety and settled agent")
    func appliesAttentionLanePrecedence() throws {
        let actionPaneId = uuid("30000000-0000-7000-8000-000000000031")
        let safetyPaneId = uuid("30000000-0000-7000-8000-000000000032")
        let settledPaneId = uuid("30000000-0000-7000-8000-000000000033")
        let atom = InboxNotificationAtom()
        atom.replaceAll([
            notification(paneId: settledPaneId, lane: .settledAgent),
            notification(paneId: safetyPaneId, lane: .safety),
            notification(paneId: actionPaneId, lane: .actionNeeded),
        ])
        let groups = [
            "settled": Set([settledPaneId]),
            "safety-over-settled": Set([safetyPaneId, settledPaneId]),
            "action-over-all": Set([actionPaneId, safetyPaneId, settledPaneId]),
        ]

        let projection = try InboxAttentionProjector.project(
            snapshot: atom.captureAttentionFacts(),
            groups: groups,
            cancellationCheck: {}
        )

        #expect(
            projection == [
                "settled": .settledAgent,
                "safety-over-settled": .safety,
                "action-over-all": .actionNeeded,
            ])
        for (groupId, paneIds) in groups {
            #expect(projection[groupId] == atom.attentionLane(forPaneIds: Array(paneIds)))
        }
    }

    private func notification(
        paneId: UUID,
        lane: InboxNotificationClaimLane,
        isRead: Bool = false,
        isDismissedFromPaneInbox: Bool = false
    ) -> InboxNotification {
        InboxNotification(
            id: UUIDv7.generate(),
            timestamp: Date(timeIntervalSince1970: 1000),
            kind: kind(for: lane),
            title: "Test",
            body: nil,
            source: .pane(.init(paneId: paneId)),
            claimKey: .init(
                paneId: paneId,
                lane: lane,
                semantic: semantic(for: lane),
                sessionId: nil
            ),
            isRead: isRead,
            isDismissedFromPaneInbox: isDismissedFromPaneInbox
        )
    }

    private func kind(for lane: InboxNotificationClaimLane) -> InboxNotificationKind {
        switch lane {
        case .actionNeeded:
            return .approvalRequested
        case .safety:
            return .securityEvent
        case .settledAgent:
            return .agentSettledActivity
        case .activity:
            return .unseenActivity
        }
    }

    private func semantic(for lane: InboxNotificationClaimLane) -> InboxNotificationClaimSemantic {
        switch lane {
        case .actionNeeded:
            return .approvalRequested
        case .safety:
            return .securityEvent
        case .settledAgent:
            return .agentSettled
        case .activity:
            return .unseenActivity
        }
    }

    private func uuid(_ value: String) -> UUID {
        // These fixed UUIDv7-form identifiers make group membership hand-checkable.
        UUID(uuidString: value)!
    }
}
