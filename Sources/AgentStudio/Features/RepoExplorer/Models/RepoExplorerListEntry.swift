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
    case sectionHeader(RepoExplorerSidebarSectionKind)
    case loadingSectionHeader(RepoExplorerSidebarSectionKind)
    case loadingRepoRow(section: RepoExplorerSidebarSectionKind, repo: RepoPresentationItem)
    case resolvedGroupHeader(RepoPresentationGroup)
    case resolvedWorktreeRow(groupId: String, repoId: UUID, worktreeId: UUID, rowId: String)
    case resolvedPaneRow(groupId: String, identity: RepoExplorerPaneListEntryIdentity, rowId: String)
    case topologyFault(RepoExplorerTopologyFault)

    var id: String {
        switch self {
        case .sectionHeader(let kind):
            return "section-header:\(kind.rawValue)"
        case .loadingSectionHeader(let kind):
            return "loading-header:\(kind.rawValue)"
        case .loadingRepoRow(let section, let repo):
            return "loading-repo:\(section.rawValue):\(repo.id.uuidString)"
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
