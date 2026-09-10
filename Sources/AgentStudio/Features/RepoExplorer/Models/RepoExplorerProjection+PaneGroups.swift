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

    static func tabPaneGroups(
        repos: [RepoPresentationItem],
        destinationsByWorktreeId: [UUID: [RepoExplorerPaneDestination]],
        unassociatedPaneDestinations: [RepoExplorerUnassociatedPaneDestination],
        paneRowFactsByPaneId: [UUID: RepoExplorerPaneRowFacts],
        tabGroupFactsByTabId: [UUID: RepoExplorerTabGroupFacts],
        branchFacts: RepoExplorerPaneBranchProjectionFacts
    ) -> (groups: [RepoPresentationGroup], paneRowsByGroupId: [String: [RepoExplorerProjectedPaneRow]]) {
        var reposById: [UUID: RepoPresentationItem] = [:]
        var destinationByPaneId: [UUID: RepoExplorerProjectedPaneDestination] = [:]
        for repo in repos {
            reposById[repo.id] = repo
            for worktree in repo.worktrees {
                for destination in destinationsByWorktreeId[worktree.id, default: []] {
                    destinationByPaneId[destination.paneId] = .associated(destination)
                }
            }
        }
        for destination in unassociatedPaneDestinations where destinationByPaneId[destination.paneId] == nil {
            destinationByPaneId[destination.paneId] = .unassociated(destination)
        }
        let destinationsByTabId = Dictionary(grouping: destinationByPaneId.values, by: \.tabId)

        var rowsByGroupId: [String: [RepoExplorerProjectedPaneRow]] = [:]
        let orderedTabs = destinationsByTabId.keys.sorted { lhs, rhs in
            let lhsIndex = destinationsByTabId[lhs]?.map(\.tabIndex).min() ?? .max
            let rhsIndex = destinationsByTabId[rhs]?.map(\.tabIndex).min() ?? .max
            return lhsIndex == rhsIndex ? lhs.uuidString < rhs.uuidString : lhsIndex < rhsIndex
        }
        let groups = orderedTabs.compactMap { tabId -> RepoPresentationGroup? in
            let destinations = (destinationsByTabId[tabId] ?? []).sorted { lhs, rhs in
                paneRowPrecedes(lhs, rhs, paneRowFactsByPaneId: paneRowFactsByPaneId, usesRecency: false)
            }
            guard !destinations.isEmpty else { return nil }
            let groupId = "tab:\(tabId.uuidString)"
            rowsByGroupId[groupId] = destinations.map { destination in
                tabPaneRow(
                    groupId: groupId,
                    destination: destination,
                    reposById: reposById,
                    paneFacts: paneRowFactsByPaneId[destination.paneId],
                    branchFacts: branchFacts
                )
            }
            let groupRepos = destinations.reduce(into: [RepoPresentationItem]()) { result, destination in
                guard let repoId = destination.repoId, let repo = reposById[repoId],
                    !result.contains(where: { $0.id == repo.id })
                else { return }
                result.append(repo)
            }
            let fallbackOrdinal = (destinations.map(\.tabIndex).min() ?? 0) + 1
            return RepoPresentationGroup(
                id: groupId,
                repoTitle: tabGroupFactsByTabId[tabId]?.displayTitle ?? "Tab \(fallbackOrdinal)",
                organizationName: "\(destinations.count) \(destinations.count == 1 ? "pane" : "panes")",
                repos: groupRepos
            )
        }
        return (groups, rowsByGroupId)
    }

    private static func tabPaneRow(
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
