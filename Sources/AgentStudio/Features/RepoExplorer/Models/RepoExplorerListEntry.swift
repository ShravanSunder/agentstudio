import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Foundation

struct RepoExplorerPaneListEntryIdentity: Equatable, Sendable {
    let repoId: UUID?
    let worktreeId: UUID?
    let paneId: UUID
}

enum RepoExplorerListEntry: Identifiable, Equatable, Sendable {
    case sectionHeader(RepoExplorerSidebarSectionKind)
    case loadingSectionHeader(RepoExplorerSidebarSectionKind)
    case loadingRepoRow(section: RepoExplorerSidebarSectionKind, repo: RepoPresentationItem)
    case resolvedGroupHeader(RepoPresentationGroup)
    case resolvedWorktreeRow(groupId: String, repoId: UUID, worktreeId: UUID, rowId: RepoExplorerRowID)
    case resolvedPaneRow(groupId: String, identity: RepoExplorerPaneListEntryIdentity, rowId: RepoExplorerRowID)
    case unassociatedPaneRow(RepoExplorerUnassociatedPaneDestination)
    case topologyFault(RepoExplorerTopologyFault)

    var id: RepoExplorerRowID {
        switch self {
        case .sectionHeader(let kind):
            return .sectionHeader(kind)
        case .loadingSectionHeader(let kind):
            return .loadingSectionHeader(kind)
        case .loadingRepoRow(let section, let repo):
            return .loadingRepository(section: section, repoID: repo.id)
        case .resolvedGroupHeader(let group):
            return .group(groupID: group.id)
        case .resolvedWorktreeRow(_, _, _, let rowId):
            return rowId
        case .resolvedPaneRow(_, _, let rowId):
            return rowId
        case .unassociatedPaneRow(let destination):
            return .unassociatedPane(paneID: destination.paneId)
        case .topologyFault:
            return .topologyFault
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
