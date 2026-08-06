import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Foundation

struct RepoExplorerPaneListEntryIdentity: Equatable, Sendable {
    let repoId: UUID
    let worktreeId: UUID
    let paneId: UUID
}

enum RepoExplorerListEntry: Identifiable, Equatable, Sendable {
    case resolvedGroupHeader(RepoPresentationGroup)
    case resolvedWorktreeRow(groupId: String, repoId: UUID, worktreeId: UUID, rowId: String)
    case resolvedPaneRow(groupId: String, identity: RepoExplorerPaneListEntryIdentity, rowId: String)
    case topologyFault(RepoExplorerTopologyFault)

    var id: String {
        switch self {
        case .resolvedGroupHeader(let group):
            return "group:\(group.id)"
        case .resolvedWorktreeRow(_, _, _, let rowId):
            return rowId
        case .resolvedPaneRow(_, _, let rowId):
            return rowId
        case .topologyFault:
            return "topology-fault"
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
