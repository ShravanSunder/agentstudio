import Foundation

extension RepoExplorerView {
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
        initialProjectionTrigger: String = "startup_diagnostic"
    ) -> String {
        guard let previous else {
            return initialProjectionTrigger == "surface_switch"
                ? "surface_switch"
                : (next.snapshot.groupingMode == .repo ? "startup_diagnostic" : "grouping_switch")
        }
        if previous.snapshot.groupingMode != next.snapshot.groupingMode {
            return "grouping_switch"
        }
        if previous.snapshot.sortOrder != next.snapshot.sortOrder {
            return "sort_order"
        }
        if previous.snapshot.query != next.snapshot.query {
            return "search"
        }
        if previous.snapshot.visibilityMode != next.snapshot.visibilityMode {
            return "visibility_mode"
        }
        if previous.expandedGroupIds != next.expandedGroupIds {
            return "collapse_toggle"
        }
        return "data_refresh"
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
        let resolvedGroupsFingerprint = projection.resolvedGroups.map { group in
            let repoIds = group.repos.map(\.id.uuidString).joined(separator: ",")
            return "\(group.id):\(repoIds)"
        }
        .joined(separator: "|")

        let loadingFingerprint = projection.loadingRepos
            .map { "\($0.id.uuidString):\($0.name)" }
            .joined(separator: "|")

        return """
            resolved[\(resolvedGroupsFingerprint)]\
            /loading[\(loadingFingerprint)]\
            /noResults[\(projection.showsNoResults)]
            """
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
