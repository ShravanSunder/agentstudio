import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceNotificationCountOwnershipTests")
struct WorkspaceNotificationCountOwnershipTests {
    @Test("pane status chips read inbox rollup alert counts")
    func paneStatusChipsReadInboxRollupAlertCounts() {
        let worktreeId = UUID()
        let staleRepoCacheCount = 9
        let inboxAtom = InboxNotificationAtom()
        inboxAtom.append(
            InboxNotification(
                id: UUID(),
                timestamp: Date(timeIntervalSince1970: 1),
                kind: .unseenActivity,
                title: "Activity",
                body: "Activity notification",
                source: .pane(
                    .init(
                        paneId: UUID(),
                        worktreeId: worktreeId,
                        worktreeName: "main"
                    )
                ),
                claimKey: .init(
                    paneId: UUID(),
                    lane: .activity,
                    semantic: .unseenActivity,
                    sessionId: UUID()
                ),
                isRead: false,
                isDismissedFromPaneInbox: false
            )
        )
        inboxAtom.append(
            InboxNotification(
                id: UUID(),
                timestamp: Date(timeIntervalSince1970: 2),
                kind: .approvalRequested,
                title: "Approval",
                body: nil,
                source: .pane(
                    .init(
                        paneId: UUID(),
                        worktreeId: worktreeId,
                        worktreeName: "main"
                    )
                ),
                claimKey: .init(
                    paneId: UUID(),
                    lane: .actionNeeded,
                    semantic: .approvalRequested,
                    sessionId: UUID()
                ),
                isRead: false,
                isDismissedFromPaneInbox: false
            )
        )

        let count = WorkspaceNotificationCountProjection.rollUpAlertCount(
            worktreeId: worktreeId,
            inboxAtom: inboxAtom
        )

        #expect(count == 1)
        #expect(count != staleRepoCacheCount)
    }
}
