import Foundation

enum InboxFilter: Equatable, Hashable, Sendable, Codable {
    case worktree(id: UUID)
    case repo(id: UUID)

    func matches(_ notification: InboxNotification) -> Bool {
        switch self {
        case .worktree(let id):
            notification.worktreeId == id
        case .repo(let id):
            notification.repoId == id
        }
    }

}
