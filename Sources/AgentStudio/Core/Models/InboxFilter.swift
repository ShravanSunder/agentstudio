import Foundation

enum InboxFilter: Equatable, Hashable, Sendable, Codable {
    case worktree(id: UUID)
    case repo(id: UUID)

    var accessibilityDescription: String {
        switch self {
        case .worktree:
            return "Worktree filter"
        case .repo:
            return "Repo filter"
        }
    }
}
