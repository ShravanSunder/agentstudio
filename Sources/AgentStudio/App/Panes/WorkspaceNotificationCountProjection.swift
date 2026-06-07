import Foundation

@MainActor
enum WorkspaceNotificationCountProjection {
    static func unreadCount(
        worktreeId: UUID,
        inboxAtom: InboxNotificationAtom
    ) -> Int {
        inboxAtom.unreadCount(forWorktreeId: worktreeId)
    }
}
