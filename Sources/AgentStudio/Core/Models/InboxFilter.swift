import Foundation

enum InboxFilter: Equatable, Hashable, Sendable, Codable {
    case worktree(id: UUID)
    case repo(id: UUID)

    func matches(worktreeId: UUID?, repoId: UUID?) -> Bool {
        switch self {
        case .worktree(let id):
            worktreeId == id
        case .repo(let id):
            repoId == id
        }
    }
}
