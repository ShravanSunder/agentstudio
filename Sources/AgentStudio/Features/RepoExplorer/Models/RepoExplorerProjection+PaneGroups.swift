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

    static func paneRepoGroups(
        repos: [RepoPresentationItem],
        metadataByRepoId: [UUID: RepoIdentityMetadata],
        sortOrder: RepoExplorerSortOrder,
        destinationsByWorktreeId: [UUID: [RepoExplorerPaneDestination]],
        paneRowFactsByPaneId: [UUID: RepoExplorerPaneRowFacts],
        branchFacts: RepoExplorerPaneBranchProjectionFacts
    ) -> (groups: [RepoPresentationGroup], paneRowsByGroupId: [String: [RepoExplorerProjectedPaneRow]]) {
        let repoGroups = repoIdentityGroups(
            repos: repos,
            metadataByRepoId: metadataByRepoId,
            sortOrder: sortOrder
        )
        var paneRowsByGroupId: [String: [RepoExplorerProjectedPaneRow]] = [:]
        let groups = repoGroups.compactMap { repoGroup -> RepoPresentationGroup? in
            guard let owningRepo = repoGroup.repos.first else { return nil }
            let destinations = repoGroup.repos
                .flatMap(\.worktrees)
                .flatMap { destinationsByWorktreeId[$0.id, default: []] }
                .sorted { lhs, rhs in
                    paneRowPrecedes(
                        lhs,
                        rhs,
                        paneRowFactsByPaneId: paneRowFactsByPaneId,
                        usesRecency: true
                    )
                }
            guard !destinations.isEmpty else { return nil }

            let groupId = "pane-repo:\(owningRepo.id.uuidString)"
            paneRowsByGroupId[groupId] = destinations.map { destination in
                RepoExplorerProjectedPaneRow(
                    groupId: groupId,
                    repoId: destination.repoId,
                    destination: destination,
                    rowId: "pane-row:\(groupId):\(destination.paneId.uuidString)",
                    primaryText: panePrimaryText(
                        destination,
                        terminalTitle: paneRowFactsByPaneId[destination.paneId]?.sidebarTerminalTitle
                    ),
                    secondaryLine: paneRowFactsByPaneId[destination.paneId]?.secondaryLine,
                    branchContextText: normalizedBranchName(
                        branchFacts.namesByWorktreeId[destination.worktreeId]
                    ),
                    branchStatus: branchFacts.statusesByWorktreeId[destination.worktreeId],
                    recencyText: paneRowFactsByPaneId[destination.paneId]?.recencyText ?? "Now",
                    recencyTier: paneRowFactsByPaneId[destination.paneId]?.recencyTier ?? .strongBlue,
                    isActive: paneRowFactsByPaneId[destination.paneId]?.isActive ?? false,
                    isDrawerPane: paneRowFactsByPaneId[destination.paneId]?.isDrawerPane ?? false
                )
            }
            return RepoPresentationGroup(
                id: groupId,
                repoTitle: repoGroup.repoTitle,
                organizationName: repoGroup.organizationName,
                repos: repoGroup.repos
            )
        }
        return (groups, paneRowsByGroupId)
    }
}
