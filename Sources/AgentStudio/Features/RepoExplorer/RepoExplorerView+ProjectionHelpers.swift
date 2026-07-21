import Foundation

extension RepoExplorerView {
    func makeSidebarSnapshot(
        repos: [RepoPresentationItem],
        repoEnrichmentByRepoId: [UUID: RepoEnrichment],
        groupingMode: RepoExplorerGroupingMode,
        sortOrder: RepoExplorerSortOrder,
        visibilityMode: RepoExplorerVisibilityMode,
        query: String
    ) -> RepoExplorerSnapshot {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        let paneLocationsByWorktreeId = atom(\.workspaceLookup).paneLocationsByWorktreeId(
            workspacePane: store.paneAtom,
            workspaceTab: workspaceTab
        )
        return RepoExplorerSnapshot(
            repos: repos,
            repoEnrichmentByRepoId: repoEnrichmentByRepoId,
            groupingMode: groupingMode,
            sortOrder: sortOrder,
            visibilityMode: visibilityMode,
            query: query,
            paneLocationsByWorktreeId: paneLocationsByWorktreeId,
            bridgePaneCommandCandidatesByWorktreeId: bridgePaneCommandCandidatesByWorktreeId(
                paneLocationsByWorktreeId: paneLocationsByWorktreeId
            )
        )
    }

    func bridgePaneCommandCandidatesByWorktreeId(
        paneLocationsByWorktreeId: [UUID: [WorkspacePaneLocation]]
    ) -> [UUID: [BridgePaneCommandCandidate]] {
        let panesByPaneId = store.paneAtom.panes
        let activeTabId = store.tabLayoutAtom.activeTabId
        let activePaneId = activeTabId.flatMap { store.tabLayoutAtom.tab($0)?.activePaneId }
        let attendanceAtom = atom(\.bridgePaneAttendance)
        var candidatesByWorktreeId: [UUID: [BridgePaneCommandCandidate]] = [:]
        candidatesByWorktreeId.reserveCapacity(paneLocationsByWorktreeId.count)

        for (worktreeId, paneLocations) in paneLocationsByWorktreeId {
            candidatesByWorktreeId[worktreeId] = paneLocations.compactMap { location in
                guard let pane = panesByPaneId[location.paneId] else { return nil }
                let isBridgePane: Bool
                if case .bridgePanel = pane.content {
                    isBridgePane = true
                } else {
                    isBridgePane = false
                }
                return BridgePaneCommandCandidate(
                    paneId: pane.id,
                    worktreeId: worktreeId,
                    isBridgePane: isBridgePane,
                    isPaneActive: pane.residency == .active,
                    isCurrentActivePane: activeTabId == location.tabId && activePaneId == pane.id,
                    attendanceOrdinal: attendanceAtom.ordinal(for: pane.id),
                    tabIndex: location.tabIndex,
                    paneIndexInTab: location.paneIndexInTab
                )
            }
        }

        return candidatesByWorktreeId
    }

    static func checkoutColorHex(
        for repo: RepoPresentationItem,
        in group: RepoPresentationGroup
    ) -> String {
        RepoPresentationColoring.checkoutColorHex(
            for: repo,
            in: group
        )
    }

    static func sourceGroupIcon(
        for group: RepoPresentationGroup,
        groupingMode: RepoExplorerGroupingMode = .repo
    ) -> AppEntityIcon {
        switch groupingMode {
        case .pane:
            return .paneGroup
        case .tab:
            return .tabGroup
        case .repo:
            break
        }

        guard
            let colorHex = RepoPresentationColoring.sourceGroupColorHex(
                for: group
            )
        else {
            return .repo
        }
        return .coloredRepo(
            colorHex: colorHex
        )
    }

    static func groupIcon(
        for group: RepoPresentationGroup,
        projectionGroupingMode: RepoExplorerGroupingMode
    ) -> AppEntityIcon {
        sourceGroupIcon(
            for: group,
            groupingMode: projectionGroupingMode
        )
    }

    static func sidebarProjectionTrigger(
        previous: RepoExplorerProjectionRequest?,
        next: RepoExplorerProjectionRequest,
        initialProjectionTrigger: AppPolicies.SidebarProjection.Trigger = .startupDiagnostic
    ) -> AppPolicies.SidebarProjection.Trigger {
        guard let previous else {
            return initialProjectionTrigger == .surfaceSwitch
                ? .surfaceSwitch
                : (next.snapshot.groupingMode == .repo ? .startupDiagnostic : .groupingSwitch)
        }
        if previous.snapshot.groupingMode != next.snapshot.groupingMode {
            return .groupingSwitch
        }
        if previous.snapshot.sortOrder != next.snapshot.sortOrder {
            return .sortOrder
        }
        if previous.snapshot.query != next.snapshot.query {
            return .search
        }
        if previous.snapshot.visibilityMode != next.snapshot.visibilityMode {
            return .visibilityMode
        }
        if previous.expandedGroupIds != next.expandedGroupIds {
            return .collapseToggle
        }
        return .dataRefresh
    }

    static func buildRepoMetadata(
        repos: [RepoPresentationItem],
        repoEnrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> [UUID: RepoIdentityMetadata] {
        RepoPresentationColoring.buildRepoMetadata(
            repos: repos,
            repoEnrichmentByRepoId: repoEnrichmentByRepoId
        )
    }

    static func buildListEntries(
        groups: [RepoPresentationGroup],
        expandedGroupIds: Set<String>,
        isFiltering: Bool
    ) -> [RepoExplorerListEntry] {
        RepoExplorerRowIndex.buildListEntries(
            groups: groups,
            expandedGroupIds: expandedGroupIds,
            isFiltering: isFiltering
        )
    }

    static func projectionFingerprint(for projection: SidebarProjection) -> String {
        let resolvedGroupsFingerprint = projection.resolvedGroups.enumerated().map { groupIndex, group in
            let reposFingerprint = group.repos.map { repo in
                let worktreesFingerprint = repo.worktrees.map { worktree in
                    "\(worktree.id.uuidString):\(worktree.name):\(worktree.path.path):\(worktree.isMainWorktree)"
                }
                .joined(separator: ",")
                return "\(repo.id.uuidString):\(repo.name):\(repo.repoPath.path):\(worktreesFingerprint)"
            }
            .joined(separator: ";")
            return "\(groupIndex):\(group.id):\(group.repoTitle):\(group.organizationName ?? ""):\(reposFingerprint)"
        }
        .joined(separator: "|")

        let loadingFingerprint = projection.loadingRepos
            .enumerated()
            .map { index, repo in
                "\(index):\(repo.id.uuidString):\(repo.name):\(repo.repoPath.path):\(repo.isFavorite)"
            }
            .joined(separator: "|")

        let projectedRowsFingerprint = projection.worktreeRowsByGroupId.keys.sorted().map { groupId in
            let rows = projection.worktreeRowsByGroupId[groupId, default: []].map { row in
                let placement =
                    row.placementContext.map {
                        "\($0.paneId.uuidString):\($0.tabId.uuidString):\($0.tabIndex):\($0.paneIndexInTab):\($0.isActiveInTab)"
                    } ?? "unattached"
                return
                    "\(row.groupId):\(row.rowId):\(row.repo.id.uuidString):\(row.worktree.id.uuidString):\(row.checkoutColorHex):\(placement)"
            }.joined(separator: ",")
            return "\(groupId):\(rows)"
        }.joined(separator: "|")

        return """
            resolved[\(resolvedGroupsFingerprint)]\
            /loading[\(loadingFingerprint)]\
            /rows[\(projectedRowsFingerprint)]\
            /emptyState[\(String(describing: projection.emptyState))]
            """
    }

    static func shouldReportInitialProjection(hasReportedInitialProjection: Bool) -> Bool {
        !hasReportedInitialProjection
    }

    static func projectSidebar(
        repos: [RepoPresentationItem],
        repoEnrichmentByRepoId: [UUID: RepoEnrichment],
        groupingMode: RepoExplorerGroupingMode = .repo,
        query: String
    ) -> SidebarProjection {
        RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: repos,
                repoEnrichmentByRepoId: repoEnrichmentByRepoId,
                groupingMode: groupingMode,
                query: query
            )
        )
    }

    static func resolvedRepos(
        _ repos: [RepoPresentationItem],
        enrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> [RepoPresentationItem] {
        RepoExplorerProjection.resolvedRepos(repos, enrichmentByRepoId: enrichmentByRepoId)
    }

    static func loadingRepos(
        _ repos: [RepoPresentationItem],
        enrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> [RepoPresentationItem] {
        RepoExplorerProjection.loadingRepos(repos, enrichmentByRepoId: enrichmentByRepoId)
    }

    static func primaryRepoForGroup(_ group: RepoPresentationGroup) -> RepoPresentationItem? {
        RepoPresentationColoring.primaryRepoForSourceGroup(group)
    }

    static func mergeBranchStatuses(
        worktreeEnrichmentsByWorktreeId: [UUID: WorktreeEnrichment],
        pullRequestCountsByWorktreeId: [UUID: Int]
    ) -> [UUID: GitBranchStatus] {
        GitBranchStatus.merge(
            worktreeEnrichmentsByWorktreeId: worktreeEnrichmentsByWorktreeId,
            pullRequestCountsByWorktreeId: pullRequestCountsByWorktreeId
        )
    }

    static func branchStatus(
        enrichment: WorktreeEnrichment?,
        pullRequestCount: Int?
    ) -> GitBranchStatus {
        GitBranchStatus.status(enrichment: enrichment, pullRequestCount: pullRequestCount)
    }

    static func sortedWorktrees(for repo: RepoPresentationItem) -> [Worktree] {
        RepoExplorerRowIndex.sortedWorktrees(for: repo)
    }
}
