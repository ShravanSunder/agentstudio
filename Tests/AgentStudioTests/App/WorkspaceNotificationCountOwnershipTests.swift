import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceNotificationCountOwnershipTests")
struct WorkspaceNotificationCountOwnershipTests {
    @Test("pane status chips read inbox unread counts")
    func paneStatusChipsReadInboxUnreadCounts() {
        let worktreeId = UUID()
        let staleRepoCacheCount = 9
        let inboxAtom = InboxNotificationAtom()
        inboxAtom.append(
            InboxNotification(
                id: UUID(),
                timestamp: Date(timeIntervalSince1970: 1),
                kind: .unseenActivity,
                title: "Unread",
                body: "Unread notification",
                source: .pane(
                    .init(
                        paneId: UUID(),
                        worktreeId: worktreeId,
                        worktreeName: "main"
                    )
                ),
                isRead: false,
                isDismissedFromPaneInbox: false
            )
        )

        let count = WorkspaceNotificationCountProjection.unreadCount(
            worktreeId: worktreeId,
            inboxAtom: inboxAtom
        )

        #expect(count == 1)
        #expect(count != staleRepoCacheCount)
    }
}
