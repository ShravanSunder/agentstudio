import Foundation

enum RepoExplorerListEntry: Identifiable, Equatable, Sendable {
    case resolvedGroupHeader(RepoPresentationGroup)
    case resolvedWorktreeRow(groupId: String, repoId: UUID, worktreeId: UUID, rowId: String)
    case topologyFault(RepoExplorerTopologyFault)

    var id: String {
        switch self {
        case .resolvedGroupHeader(let group):
            return "group:\(group.id)"
        case .resolvedWorktreeRow(_, _, _, let rowId):
            return rowId
        case .topologyFault:
            return "topology-fault"
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
