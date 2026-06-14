import Foundation

enum RepoExplorerListEntry: Identifiable, Equatable {
    case resolvedGroupHeader(RepoPresentationGroup)
    case resolvedWorktreeRow(groupId: String, repoId: UUID, worktreeId: UUID)

    var id: String {
        switch self {
        case .resolvedGroupHeader(let group):
            return "group:\(group.id)"
        case .resolvedWorktreeRow(let groupId, let repoId, let worktreeId):
            return "worktree:\(groupId):\(repoId.uuidString):\(worktreeId.uuidString)"
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
