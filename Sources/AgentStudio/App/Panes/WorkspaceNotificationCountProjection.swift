import Foundation

@MainActor
enum WorkspaceNotificationCountProjection {
    static func rollUpAlertCount(
        worktreeId: UUID,
        inboxAtom: InboxNotificationAtom
    ) -> Int {
        inboxAtom.rollUpAlertCount(forWorktreeId: worktreeId)
    }

    static func unreadCount(
        worktreeId: UUID,
        inboxAtom: InboxNotificationAtom
    ) -> Int {
        inboxAtom.unreadCount(forWorktreeId: worktreeId)
    }
}
