import Foundation

enum InboxNotificationReadScope: Sendable, Equatable {
    case workspace
    case repo(UUID)
    case worktree(UUID)
    case paneIds([UUID])

    func matches(_ notification: InboxNotification) -> Bool {
        switch self {
        case .workspace:
            return true
        case .repo(let repoId):
            return notification.repoId == repoId
        case .worktree(let worktreeId):
            return notification.worktreeId == worktreeId
        case .paneIds(let paneIds):
            guard let paneId = notification.paneId else { return false }
            return paneIds.contains(paneId)
        }
    }
}
