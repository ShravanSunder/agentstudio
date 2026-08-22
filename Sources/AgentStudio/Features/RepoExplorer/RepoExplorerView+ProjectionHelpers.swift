import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Foundation

struct RepoExplorerProjectionRequestKey: Equatable {
    let snapshot: RepoExplorerSnapshot
    let collapsedGroupIds: Set<String>
    let isFiltering: Bool
    let worktreeEnrichmentSnapshot: [UUID: WorktreeEnrichment]
    let pullRequestFactsSnapshot: [RepoBranchKey: PullRequestFacts]
    let paneRowFactsByPaneId: [UUID: RepoExplorerPaneRowFacts]
    let tabGroupFactsByTabId: [UUID: RepoExplorerTabGroupFacts]
    /// Must be compared explicitly: a repo can resolve to terminal pull-request unavailability with
    /// zero change to its (empty) facts snapshot, so omitting this field would let that transition
    /// compare equal and silently skip re-projection.
    let unavailablePullRequestRepoIds: Set<UUID>
    let loadingPullRequestRepoIds: Set<UUID>
}

extension RepoExplorerView {
    static func paneSecondaryText(
        liveTitle: String,
        cwd: URL?,
        shellExecutablePath: String?
    ) -> String {
        let normalizedTitle = liveTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let cwdPath = cwd?.standardizedFileURL.path
        let titleIsPathShaped =
            normalizedTitle.hasPrefix("/")
            || normalizedTitle.hasPrefix("~")
            || normalizedTitle.hasPrefix("…/")
            || normalizedTitle.hasPrefix(".../")
        let titleMatchesCWD =
            cwdPath.map { cwdPath in
                normalizedTitle == cwdPath || normalizedTitle.hasPrefix("\(cwdPath)/")
            } ?? false
        guard normalizedTitle.isEmpty || titleIsPathShaped || titleMatchesCWD else {
            return normalizedTitle
        }

        let shellName = shellExecutablePath.flatMap { shellExecutablePath -> String? in
            let lastPathComponent = URL(fileURLWithPath: shellExecutablePath).lastPathComponent
            return lastPathComponent.isEmpty ? nil : lastPathComponent
        }
        return shellName ?? "zsh"
    }

    static func measureRowBodyEvaluationProxy<Content>(
        rowKind: RepoExplorerRowKind,
        nowNanoseconds: () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        resolve: () -> Content
    ) -> RepoExplorerRowBodyEvaluationMeasurement<Content> {
        let startedAtNanoseconds = nowNanoseconds()
        let content = resolve()
        let completedAtNanoseconds = nowNanoseconds()
        return RepoExplorerRowBodyEvaluationMeasurement(
            content: content,
            duration: .nanoseconds(
                Int64(clamping: completedAtNanoseconds - min(completedAtNanoseconds, startedAtNanoseconds))
            ),
            rowKind: rowKind,
            outcome: .success
        )
    }

    static func measureOutlineApplyProxy(
        previousRowIDs: [String],
        nextRowIDs: [String],
        nowNanoseconds: () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        apply: () -> Void
    ) -> RepoExplorerOutlineApplyMeasurement {
        let startedAtNanoseconds = nowNanoseconds()
        apply()
        let completedAtNanoseconds = nowNanoseconds()
        let previousIndexByRowID = Dictionary(
            uniqueKeysWithValues: previousRowIDs.enumerated().map { ($0.element, $0.offset) }
        )
        let nextIndexByRowID = Dictionary(
            uniqueKeysWithValues: nextRowIDs.enumerated().map { ($0.element, $0.offset) }
        )
        let changedRowCount = Set(previousIndexByRowID.keys).union(nextIndexByRowID.keys).count { rowID in
            previousIndexByRowID[rowID] != nextIndexByRowID[rowID]
        }
        let isContentIdentical = previousRowIDs == nextRowIDs
        return RepoExplorerOutlineApplyMeasurement(
            duration: .nanoseconds(
                Int64(clamping: completedAtNanoseconds - min(completedAtNanoseconds, startedAtNanoseconds))
            ),
            totalRowCount: nextRowIDs.count,
            changedRowCount: changedRowCount,
            equalPublishCount: isContentIdentical ? 1 : 0,
            outcome: isContentIdentical ? .equal : .changed
        )
    }

    static func measureSuppressedOutlineApplyProxy(rowCount: Int) -> RepoExplorerOutlineApplyMeasurement {
        RepoExplorerOutlineApplyMeasurement(
            duration: .zero,
            totalRowCount: rowCount,
            changedRowCount: 0,
            equalPublishCount: 1,
            outcome: .suppressed
        )
    }

    static func projectionRequestKey(
        for request: RepoExplorerProjectionRequest
    ) -> RepoExplorerProjectionRequestKey {
        RepoExplorerProjectionRequestKey(
            snapshot: request.snapshot,
            collapsedGroupIds: request.collapsedGroupIds,
            isFiltering: request.isFiltering,
            worktreeEnrichmentSnapshot: request.worktreeEnrichmentSnapshot,
            pullRequestFactsSnapshot: request.pullRequestFactsSnapshot,
            paneRowFactsByPaneId: request.paneRowFactsByPaneId,
            tabGroupFactsByTabId: request.tabGroupFactsByTabId,
            unavailablePullRequestRepoIds: request.unavailablePullRequestRepoIds,
            loadingPullRequestRepoIds: request.loadingPullRequestRepoIds
        )
    }

    func sidebarProjectionTraceAttributes(
        for request: RepoExplorerProjectionRequest,
        phase: String,
        extra: [String: AgentStudioTraceValue] = [:]
    ) -> [String: AgentStudioTraceValue] {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.performance.sidebar.surface": .string("repo"),
            "agentstudio.performance.sidebar.phase": .string(phase),
            "agentstudio.performance.sidebar.trigger": .string(request.trigger.rawValue),
            "agentstudio.performance.sidebar.query_state": .string(
                request.snapshot.query.isEmpty ? "empty" : "non_empty"),
            "agentstudio.performance.sidebar.group_mode": .string(request.snapshot.groupingMode.rawValue),
            "agentstudio.performance.sidebar.sort_order": .string(request.snapshot.sortOrder.rawValue),
            "agentstudio.performance.sidebar.repo.count": .int(request.snapshot.repos.count),
            "agentstudio.performance.sidebar.query_character.count": .int(request.snapshot.query.count),
            "agentstudio.performance.sidebar.collapsed_group.count": .int(request.collapsedGroupIds.count),
            "agentstudio.performance.sidebar.is_filtering": .bool(request.isFiltering),
        ]
        attributes.merge(extra) { _, newValue in newValue }
        return attributes
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
        for _: RepoPresentationGroup,
        groupingMode: RepoExplorerGroupingMode = .repo
    ) -> AppEntityIcon {
        switch groupingMode {
        case .pane, .repo:
            return .repo
        case .tab:
            return .tabGroup
        }
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
        if previous.collapsedGroupIds != next.collapsedGroupIds {
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
        collapsedGroupIds: Set<String>,
        isFiltering: Bool
    ) -> [RepoExplorerListEntry] {
        RepoExplorerRowIndex.buildListEntries(
            groups: groups,
            collapsedGroupIds: collapsedGroupIds,
            isFiltering: isFiltering
        )
    }

    static func projectionFingerprint(for projection: SidebarProjection) -> String {
        let sectionsFingerprint = projection.sections.enumerated().map { sectionIndex, section in
            let resolvedGroups = section.resolvedGroups.map { group in
                let repos = group.repos.map { repo in
                    "\(repo.id.uuidString):\(repo.isFavorite)"
                }.joined(separator: ",")
                return "\(group.id):\(repos)"
            }.joined(separator: ";")
            let loadingRepos = section.loadingRepos.map { repo in
                "\(repo.id.uuidString):\(repo.isFavorite)"
            }.joined(separator: ",")
            let unassociatedPanes = section.unassociatedPaneDestinations.map { destination in
                "\(destination.paneId.uuidString):\(destination.tabId.uuidString):\(destination.tabIndex):\(destination.paneIndexInTab):\(destination.isActiveInTab)"
            }.joined(separator: ",")
            return
                "\(sectionIndex):\(section.kind.rawValue):\(resolvedGroups):\(loadingRepos):\(unassociatedPanes)"
        }
        .joined(separator: "|")

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

        let projectedPaneRowsFingerprint = projection.paneRowsByGroupId.keys.sorted().map { groupId in
            let rows = projection.paneRowsByGroupId[groupId, default: []].map { row in
                let secondaryLineFingerprint =
                    switch row.secondaryLine {
                    case .note(let text): "note:\(text)"
                    case .terminalOutput(let text): "terminal:\(text)"
                    case nil: "none"
                    }
                let branchStatusFingerprint = paneBranchStatusFingerprint(row.branchStatus)
                return
                    "\(row.groupId):\(row.rowId):\(row.primaryText):\(secondaryLineFingerprint):\(row.branchContextText ?? ""):\(branchStatusFingerprint):\(row.recencyText):\(paneRecencyTierFingerprint(row.recencyTier)):\(row.isActive):\(row.isDrawerPane):\(paneDestinationFingerprint(row.destination))"
            }.joined(separator: ",")
            return "\(groupId):\(rows)"
        }.joined(separator: "|")

        let worktreeDestinationsFingerprint = projection.paneDestinationsByWorktreeId.keys
            .sorted { $0.uuidString < $1.uuidString }
            .map { worktreeId in
                let destinations = projection.paneDestinationsByWorktreeId[worktreeId, default: []]
                    .map(paneDestinationFingerprint)
                    .joined(separator: ",")
                return "\(worktreeId.uuidString):\(destinations)"
            }
            .joined(separator: "|")

        let repoDestinationsFingerprint = projection.paneDestinationsByRepoId.keys
            .sorted { $0.uuidString < $1.uuidString }
            .map { repoId in
                let destinations = projection.paneDestinationsByRepoId[repoId, default: []]
                    .map(paneDestinationFingerprint)
                    .joined(separator: ",")
                return "\(repoId.uuidString):\(destinations)"
            }
            .joined(separator: "|")

        return """
            sections[\(sectionsFingerprint)]\
            /resolved[\(resolvedGroupsFingerprint)]\
            /loading[\(loadingFingerprint)]\
            /rows[\(projectedRowsFingerprint)]\
            /paneRows[\(projectedPaneRowsFingerprint)]\
            /worktreePaneDestinations[\(worktreeDestinationsFingerprint)]\
            /repoPaneDestinations[\(repoDestinationsFingerprint)]\
            /emptyState[\(String(describing: projection.emptyState))]
            """
    }

    private static func paneDestinationFingerprint(_ destination: RepoExplorerPaneDestination) -> String {
        "\(destination.paneId.uuidString):\(destination.repoId.uuidString):\(destination.worktreeId.uuidString):\(destination.worktreeLabel):\(destination.paneDisplayLabel):\(destination.tabId.uuidString):\(destination.tabIndex):\(destination.paneIndexInTab):\(destination.isActiveInTab)"
    }

    private static func paneBranchStatusFingerprint(_ status: GitBranchStatus?) -> String {
        guard let status else { return "none" }
        let syncFingerprint =
            switch status.syncState {
            case .synced: "synced"
            case .ahead(let count): "ahead:\(count)"
            case .behind(let count): "behind:\(count)"
            case .diverged(let ahead, let behind): "diverged:\(ahead):\(behind)"
            case .noUpstream: "no-upstream"
            case .unknown: "unknown"
            }
        return
            "\(status.isDirty):\(syncFingerprint):\(status.prCount.map(String.init) ?? "nil"):\(status.pullRequestIsLoading):\(status.pullRequestDataUnavailable):\(status.linesAdded):\(status.linesDeleted):\(status.untrackedFileCount)"
    }

    private static func paneRecencyTierFingerprint(_ tier: RepoExplorerPaneRecencyTier) -> String {
        switch tier {
        case .strongBlue: "strong-blue"
        case .mediumBlue: "medium-blue"
        case .mutedBlue: "muted-blue"
        case .faintBlue: "faint-blue"
        case .grey: "grey"
        }
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

    package static func resolvedRepos(
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

    static func semanticRepoForHeader(
        _ group: RepoPresentationGroup,
        groupingMode: RepoExplorerGroupingMode
    ) -> RepoPresentationItem? {
        guard groupingMode == .repo || groupingMode == .pane, group.repos.count == 1 else { return nil }
        return group.repos.first
    }

    func panePresentation(for destination: RepoExplorerPaneDestination) -> RepoExplorerPanePresentation {
        RepoExplorerPanePresentation(
            destination: destination,
            label: destination.label
        )
    }

    func panePresentations(
        _ destinations: [RepoExplorerPaneDestination]
    ) -> [RepoExplorerPanePresentation] {
        destinations.map(panePresentation(for:))
    }

    func focusPane(_ paneId: UUID) {
        commandDispatcher.dispatch(.focusPane, target: paneId, targetType: .pane)
    }

    static func mergeBranchStatuses(
        worktreeEnrichmentsByWorktreeId: [UUID: WorktreeEnrichment],
        pullRequestFactsByBranch: [RepoBranchKey: PullRequestFacts],
        unavailablePullRequestRepoIds: Set<UUID> = []
    ) -> [UUID: GitBranchStatus] {
        GitBranchStatus.merge(
            worktreeEnrichmentsByWorktreeId: worktreeEnrichmentsByWorktreeId,
            pullRequestFactsByBranch: pullRequestFactsByBranch,
            unavailablePullRequestRepoIds: unavailablePullRequestRepoIds
        )
    }

    package static func branchStatus(
        enrichment: WorktreeEnrichment?,
        pullRequestFacts: PullRequestFacts?
    ) -> GitBranchStatus {
        GitBranchStatus.status(enrichment: enrichment, pullRequestFacts: pullRequestFacts)
    }

    static func sortedWorktrees(for repo: RepoPresentationItem) -> [Worktree] {
        RepoExplorerRowIndex.sortedWorktrees(for: repo)
    }
}
