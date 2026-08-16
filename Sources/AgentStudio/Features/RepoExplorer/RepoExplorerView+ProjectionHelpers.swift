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
        let cwdLeaf = cwd.flatMap { cwd -> String? in
            let lastPathComponent = cwd.lastPathComponent
            return lastPathComponent.isEmpty ? nil : lastPathComponent
        }
        let fallbackParts = [shellName, cwdLeaf].compactMap { $0 }
        return fallbackParts.isEmpty ? "Terminal" : fallbackParts.joined(separator: " — ")
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

    static func worktreeEnrichmentSnapshot(
        for worktreeIds: [UUID],
        repoCache: RepoCacheAtom
    ) -> [UUID: WorktreeEnrichment] {
        var enrichmentByWorktreeId: [UUID: WorktreeEnrichment] = [:]
        enrichmentByWorktreeId.reserveCapacity(worktreeIds.count)
        for worktreeId in worktreeIds {
            enrichmentByWorktreeId[worktreeId] = repoCache.worktreeEnrichment(for: worktreeId)
        }
        return enrichmentByWorktreeId
    }

    static func pullRequestFactsSnapshot(
        for worktreeEnrichmentSnapshot: [UUID: WorktreeEnrichment],
        repoCache: RepoCacheAtom
    ) -> [RepoBranchKey: PullRequestFacts] {
        var factsByBranch: [RepoBranchKey: PullRequestFacts] = [:]
        for enrichment in worktreeEnrichmentSnapshot.values {
            guard let key = RepoBranchKey(repoId: enrichment.repoId, branch: enrichment.branch) else { continue }
            factsByBranch[key] = repoCache.pullRequestFacts(for: key)
        }
        return factsByBranch
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
            tabGroupFactsByTabId: request.tabGroupFactsByTabId
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

    func makeSidebarSnapshot(
        repos: [RepoPresentationItem],
        repoEnrichmentByRepoId: [UUID: RepoEnrichment],
        groupingMode: RepoExplorerGroupingMode,
        sortOrder: RepoExplorerSortOrder,
        query: String
    ) -> RepoExplorerSnapshot {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        let paneLocationsByWorktreeId = atom(\.workspaceLookup).paneLocationsByWorktreeId(
            repositoryTopology: store.repositoryTopologyAtom,
            workspacePane: store.paneAtom,
            workspaceTab: workspaceTab,
            declaredWorktreeIDs: Set(repos.flatMap(\.worktrees).map(\.id))
        )
        return RepoExplorerSnapshot(
            repos: repos,
            repoEnrichmentByRepoId: repoEnrichmentByRepoId,
            groupingMode: groupingMode,
            sortOrder: sortOrder,
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
        let paneGraph = store.paneAtom.graphAtom
        let activeTabId = store.tabLayoutAtom.activeTabId
        let activePaneId = activeTabId.flatMap { store.tabLayoutAtom.tab($0)?.activePaneId }
        var candidatesByWorktreeId: [UUID: [BridgePaneCommandCandidate]] = [:]
        candidatesByWorktreeId.reserveCapacity(paneLocationsByWorktreeId.count)

        for (worktreeId, paneLocations) in paneLocationsByWorktreeId {
            candidatesByWorktreeId[worktreeId] = paneLocations.compactMap { location -> BridgePaneCommandCandidate? in
                guard let paneFacts = paneGraph.paneStructuralFacts(location.paneId) else { return nil }
                return BridgePaneCommandCandidate(
                    paneId: paneFacts.paneID,
                    worktreeId: worktreeId,
                    isBridgePane: paneFacts.isBridgeEligible,
                    isPaneActive: paneFacts.residency == .active,
                    isCurrentActivePane: activeTabId == location.tabId && activePaneId == paneFacts.paneID,
                    attendanceOrdinal: bridgeAttendanceSnapshot(paneFacts.paneID),
                    tabIndex: location.tabIndex,
                    paneIndexInTab: location.paneIndexInTab
                )
            }
        }

        return candidatesByWorktreeId
    }

    func paneRowFactsByPaneId(now: Date = Date()) -> [UUID: RepoExplorerPaneRowFacts] {
        typealias PaneRowFactsEntry = (UUID, RepoExplorerPaneRowFacts)
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        let lastInteractionByPaneId: [UUID: Date] = Dictionary(
            uniqueKeysWithValues: atom(\.workspaceEntityRecency).recentEntities.compactMap { recency -> (UUID, Date)? in
                guard case .pane(let paneId) = recency.entity else { return nil }
                return (paneId, recency.lastInteractedAt)
            }
        )
        let activePaneIds = Set(
            store.tabLayoutAtom.activeTab.flatMap { tab in
                store.tabLayoutAtom.activePaneID(forTab: tab.id).map { [$0] }
            } ?? []
        )
        return Dictionary(
            uniqueKeysWithValues: workspaceTab.tabs.flatMap(\.allPaneIds).compactMap { paneId -> PaneRowFactsEntry? in
                guard let pane = store.paneAtom.pane(paneId) else { return nil }
                let terminalTitle = Self.paneSecondaryText(
                    liveTitle: pane.title,
                    cwd: pane.metadata.facets.cwd,
                    shellExecutablePath: pane.metadata.contentType == .terminal
                        ? SessionConfiguration.defaultShell()
                        : nil
                )
                let lastInteractedAt = lastInteractionByPaneId[paneId]
                let recencyReferenceDate = lastInteractedAt ?? pane.metadata.createdAt
                return (
                    paneId,
                    RepoExplorerPaneRowFacts(
                        terminalTitle: terminalTitle,
                        recencyReferenceDate: recencyReferenceDate,
                        recencyText: RepoExplorerPaneRecencyText.display(
                            lastInteractedAt: recencyReferenceDate,
                            now: now
                        ),
                        isActive: activePaneIds.contains(paneId)
                    )
                )
            }
        )
    }

    func tabGroupFactsByTabId() -> [UUID: RepoExplorerTabGroupFacts] {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        return Dictionary(
            uniqueKeysWithValues: workspaceTab.tabs.map { tab in
                (
                    tab.id,
                    RepoExplorerTabGroupFacts(
                        displayTitle: atom(\.tabDisplay).displayTitle(
                            for: tab,
                            workspacePane: store.paneAtom,
                            workspaceRepositoryTopology: store.repositoryTopologyAtom,
                            repoCache: atom(\.repoCache)
                        )
                    )
                )
            }
        )
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
            break
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
            return "\(sectionIndex):\(section.kind.rawValue):\(resolvedGroups):\(loadingRepos)"
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
                "\(row.groupId):\(row.rowId):\(row.primaryText):\(row.secondaryText):\(row.recencyText):\(row.isActive):\(paneDestinationFingerprint(row.destination))"
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
        pullRequestFactsByBranch: [RepoBranchKey: PullRequestFacts]
    ) -> [UUID: GitBranchStatus] {
        GitBranchStatus.merge(
            worktreeEnrichmentsByWorktreeId: worktreeEnrichmentsByWorktreeId,
            pullRequestFactsByBranch: pullRequestFactsByBranch
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
