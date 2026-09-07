import AgentStudioCore
import Foundation

struct RepoExplorerPaneBranchProjectionFacts {
    let namesByWorktreeId: [UUID: String]
    let statusesByWorktreeId: [UUID: GitBranchStatus]
}

extension RepoExplorerProjection {
    static func degradedProjectionIfTopologyFault(
        in repos: [RepoPresentationItem]
    ) -> RepoExplorerSidebarProjection? {
        var detector = RepoExplorerTopologyFaultDetector()
        for repo in repos {
            detector.observe(repo)
        }
        return detector.fault.map(RepoExplorerSidebarProjection.degraded)
    }

    static func tabPaneRow(
        groupId: String,
        destination: RepoExplorerProjectedPaneDestination,
        reposById: [UUID: RepoPresentationItem],
        paneFacts: RepoExplorerPaneRowFacts?,
        branchFacts: RepoExplorerPaneBranchProjectionFacts
    ) -> RepoExplorerProjectedPaneRow {
        switch destination {
        case .associated(let associatedDestination):
            return RepoExplorerProjectedPaneRow(
                groupId: groupId,
                repoId: associatedDestination.repoId,
                destination: associatedDestination,
                membershipOwner: .tab,
                rowId: "pane-row:\(groupId):\(destination.paneId.uuidString)",
                primaryText: panePrimaryText(destination, terminalTitle: paneFacts?.sidebarTerminalTitle),
                secondaryLine: paneFacts?.secondaryLine,
                branchContextText: normalizedBranchName(
                    branchFacts.namesByWorktreeId[associatedDestination.worktreeId]
                ).map { branchName in
                    let repoName = reposById[associatedDestination.repoId]?.name ?? "Repository"
                    return "\(repoName) · \(branchName)"
                },
                branchStatus: branchFacts.statusesByWorktreeId[associatedDestination.worktreeId],
                recencyText: paneFacts?.recencyText ?? "Now",
                recencyTier: paneFacts?.recencyTier ?? .strongBlue,
                isActive: paneFacts?.isActive ?? false,
                isDrawerPane: paneFacts?.isDrawerPane ?? false
            )
        case .unassociated(let unassociatedDestination):
            return RepoExplorerProjectedPaneRow(
                groupId: groupId,
                destination: unassociatedDestination,
                rowId: "pane-row:\(groupId):\(destination.paneId.uuidString)",
                primaryText: panePrimaryText(destination, terminalTitle: paneFacts?.sidebarTerminalTitle),
                secondaryLine: paneFacts?.secondaryLine,
                recencyText: paneFacts?.recencyText ?? "Now",
                recencyTier: paneFacts?.recencyTier ?? .strongBlue,
                isActive: paneFacts?.isActive ?? false,
                isDrawerPane: paneFacts?.isDrawerPane ?? false
            )
        }
    }
}
