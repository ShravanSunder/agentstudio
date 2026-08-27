import AgentStudioCore
import Foundation

struct RepoExplorerProjectedPaneRow: Equatable, Sendable {
    let groupId: String
    let repoId: UUID
    let destination: RepoExplorerPaneDestination
    let rowId: String
    let primaryText: String
    let secondaryLine: RepoExplorerPaneSecondaryLine?
    let branchContextText: String?
    let branchStatus: GitBranchStatus?
    let recencyText: String
    let recencyTier: RepoExplorerPaneRecencyTier
    let isActive: Bool
    let isDrawerPane: Bool

    var secondaryText: String? { secondaryLine?.text }

    init(
        groupId: String,
        repoId: UUID,
        destination: RepoExplorerPaneDestination,
        rowId: String,
        primaryText: String = "",
        secondaryLine: RepoExplorerPaneSecondaryLine? = nil,
        branchContextText: String? = nil,
        branchStatus: GitBranchStatus? = nil,
        recencyText: String = "Now",
        recencyTier: RepoExplorerPaneRecencyTier = .strongBlue,
        isActive: Bool = false,
        isDrawerPane: Bool = false
    ) {
        self.groupId = groupId
        self.repoId = repoId
        self.destination = destination
        self.rowId = rowId
        self.primaryText = primaryText
        self.secondaryLine = secondaryLine
        self.branchContextText = branchContextText
        self.branchStatus = branchStatus
        self.recencyText = recencyText
        self.recencyTier = recencyTier
        self.isActive = isActive
        self.isDrawerPane = isDrawerPane
    }
}
