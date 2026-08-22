import Foundation

enum RepoExplorerRowID: Hashable, Sendable {
    case sectionHeader(RepoExplorerSidebarSectionKind)
    case loadingSectionHeader(RepoExplorerSidebarSectionKind)
    case loadingRepository(section: RepoExplorerSidebarSectionKind, repoID: UUID)
    case group(groupID: String)
    case worktree(groupID: String, repoID: UUID, worktreeID: UUID)
    case associatedPane(groupID: String, repoID: UUID, worktreeID: UUID, paneID: UUID)
    case unassociatedPane(paneID: UUID)
    case topologyFault

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.sectionHeader(let lhsKind), .sectionHeader(let rhsKind)):
            lhsKind == rhsKind
        case (.loadingSectionHeader(let lhsKind), .loadingSectionHeader(let rhsKind)):
            lhsKind == rhsKind
        case (
            .loadingRepository(let lhsSection, let lhsRepoID),
            .loadingRepository(let rhsSection, let rhsRepoID)
        ):
            lhsSection == rhsSection && lhsRepoID == rhsRepoID
        case (.group(let lhsGroupID), .group(let rhsGroupID)):
            lhsGroupID == rhsGroupID
        case (
            .worktree(let lhsGroupID, let lhsRepoID, let lhsWorktreeID),
            .worktree(let rhsGroupID, let rhsRepoID, let rhsWorktreeID)
        ):
            lhsGroupID == rhsGroupID && lhsRepoID == rhsRepoID
                && lhsWorktreeID == rhsWorktreeID
        case (
            .associatedPane(let lhsGroupID, let lhsRepoID, let lhsWorktreeID, let lhsPaneID),
            .associatedPane(let rhsGroupID, let rhsRepoID, let rhsWorktreeID, let rhsPaneID)
        ):
            lhsGroupID == rhsGroupID && lhsRepoID == rhsRepoID
                && lhsWorktreeID == rhsWorktreeID && lhsPaneID == rhsPaneID
        case (.unassociatedPane(let lhsPaneID), .unassociatedPane(let rhsPaneID)):
            lhsPaneID == rhsPaneID
        case (.topologyFault, .topologyFault):
            true
        default:
            false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .sectionHeader(let kind):
            hasher.combine(0)
            hasher.combine(kind.rawValue)
        case .loadingSectionHeader(let kind):
            hasher.combine(1)
            hasher.combine(kind.rawValue)
        case .loadingRepository(let section, let repoID):
            hasher.combine(2)
            hasher.combine(section.rawValue)
            hasher.combine(repoID)
        case .group(let groupID):
            hasher.combine(3)
            hasher.combine(groupID)
        case .worktree(let groupID, let repoID, let worktreeID):
            hasher.combine(4)
            hasher.combine(groupID)
            hasher.combine(repoID)
            hasher.combine(worktreeID)
        case .associatedPane(let groupID, let repoID, let worktreeID, let paneID):
            hasher.combine(5)
            hasher.combine(groupID)
            hasher.combine(repoID)
            hasher.combine(worktreeID)
            hasher.combine(paneID)
        case .unassociatedPane(let paneID):
            hasher.combine(6)
            hasher.combine(paneID)
        case .topologyFault:
            hasher.combine(7)
        }
    }
}
