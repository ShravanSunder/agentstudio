import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

/// MainActor source capture owned by the Repo Explorer projection adapter.
///
/// This type reads canonical owners and produces immutable projection work. It
/// does not schedule, admit, execute, or publish projection work; those state
/// transitions remain in `RepoExplorerProjectionAdapter`.
@MainActor
final class RepoExplorerProjectionInputCapture {
    let store: WorkspaceStore
    let preferences: RepoExplorerSidebarPrefsAtom
    let repoCache: RepoCacheAtom
    let sidebarState: WorkspaceSidebarState
    let sidebarCache: SidebarCacheState
    let coreAtoms: CoreAtoms
    let bridgeAttendanceSnapshot: BridgeAttendanceSnapshot
    let latestPaneMessageSnapshot: LatestPaneMessageSnapshot

    private var paneDisplayTitleCache = RepoExplorerPaneDisplayTitleCache()

    init(
        store: WorkspaceStore,
        preferences: RepoExplorerSidebarPrefsAtom,
        repoCache: RepoCacheAtom,
        sidebarState: WorkspaceSidebarState,
        sidebarCache: SidebarCacheState,
        coreAtoms: CoreAtoms,
        bridgeAttendanceSnapshot: @escaping BridgeAttendanceSnapshot,
        latestPaneMessageSnapshot: @escaping LatestPaneMessageSnapshot
    ) {
        self.store = store
        self.preferences = preferences
        self.repoCache = repoCache
        self.sidebarState = sidebarState
        self.sidebarCache = sidebarCache
        self.coreAtoms = coreAtoms
        self.bridgeAttendanceSnapshot = bridgeAttendanceSnapshot
        self.latestPaneMessageSnapshot = latestPaneMessageSnapshot
    }

    func observeInputs(isVisible: Bool) -> RepoExplorerObservationRegistration {
        guard isVisible, sidebarState.sidebarSurface == .repos else { return .hidden }

        let repositoryIDs = store.repositoryTopologyAtom.repositoryIdsInOrder
        let groupingMode = preferences.groupingMode
        var worktreeIDs = Set<UUID>()
        _ = Self.observeRepoEnrichmentInputs(repositoryIDs: repositoryIDs, repoCache: repoCache)
        for repositoryID in repositoryIDs {
            _ = repoCache.isPullRequestLoading(forRepository: repositoryID)
            _ = repoCache.isPullRequestDataUnavailable(forRepository: repositoryID)
            guard let repository = store.repositoryTopologyAtom.repo(repositoryID) else { continue }
            for worktree in repository.worktrees {
                worktreeIDs.insert(worktree.id)
                let enrichment = repoCache.worktreeEnrichment(for: worktree.id)
                if let enrichment,
                    let branchKey = RepoBranchKey(repoId: enrichment.repoId, branch: enrichment.branch)
                {
                    _ = repoCache.pullRequestFacts(for: branchKey)
                }
            }
        }

        _ = groupingMode
        if groupingMode != .tab
            || repositoryIDs.contains(where: { repoCache.repoEnrichment(for: $0) == nil })
        {
            _ = preferences.sortOrder
        }
        _ = sidebarCache.collapsedGroups

        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        let paneGraph = store.paneAtom.graphAtom
        var paneIDs = Set<UUID>()
        var tabIDs = Set<UUID>()
        for tab in workspaceTab.tabs {
            tabIDs.insert(tab.id)
            _ = store.tabLayoutAtom.tab(tab.id)
            if groupingMode == .tab {
                _ = coreAtoms.tabDisplay.displayTitle(
                    for: tab,
                    workspacePane: store.paneAtom,
                    workspaceRepositoryTopology: store.repositoryTopologyAtom,
                    repoCache: repoCache
                )
            }
            for paneID in tab.allPaneIds {
                paneIDs.insert(paneID)
                _ = paneGraph.paneStructuralFacts(paneID)
                _ = bridgeAttendanceSnapshot(paneID)
                if groupingMode != .repo {
                    _ = store.paneAtom.pane(paneID)
                    _ = latestPaneMessageSnapshot(paneID)
                }
            }
        }
        for paneID in paneGraph.paneIDs {
            paneIDs.insert(paneID)
            _ = paneGraph.paneStructuralFacts(paneID)
        }

        if groupingMode != .repo {
            _ = coreAtoms.workspaceEntityRecency.recentEntities
            _ = KeyboardRoutingContext.current(
                windowLifecycle: coreAtoms.windowLifecycle,
                managementLayer: coreAtoms.managementLayer,
                uiState: sidebarState,
                commandBarSurface: coreAtoms.commandBarSurface,
                transientKeyboardSurface: coreAtoms.transientKeyboardSurface
            )
            _ = coreAtoms.attendedPane.attendedPaneId
        }

        return RepoExplorerObservationRegistration.make(
            isVisible: true,
            groupingMode: groupingMode,
            repositoryIDs: Set(repositoryIDs),
            worktreeIDs: worktreeIDs,
            paneIDs: paneIDs,
            tabIDs: tabIDs
        )
    }

    static func observeRepoEnrichmentInputs(
        repositoryIDs: [UUID],
        repoCache: RepoCacheAtom
    ) -> Int {
        for repositoryID in repositoryIDs {
            _ = repoCache.repoEnrichment(for: repositoryID)
        }
        return repositoryIDs.count
    }

    func captureRequest(
        query: String,
        referenceDate: Date,
        trigger: AppPolicies.SidebarProjection.Trigger
    ) -> RepoExplorerProjectionRequest {
        let repos = sidebarRepos()
        let worktreeEnrichmentSnapshot = Self.worktreeEnrichmentSnapshot(
            for: repos.flatMap(\.worktrees).map(\.id),
            repoCache: repoCache
        )
        let groupingMode = preferences.groupingMode
        let repositoryIDs = Set(repos.map(\.id))
        let snapshot = makeSidebarSnapshot(
            repos: repos,
            repoEnrichmentByRepoId: Dictionary(
                uniqueKeysWithValues: repos.compactMap { repo in
                    repoCache.repoEnrichment(for: repo.id).map { (repo.id, $0) }
                }
            ),
            groupingMode: groupingMode,
            sortOrder: preferences.sortOrder,
            query: query
        )
        return RepoExplorerProjectionRequest(
            generation: 0,
            snapshot: snapshot,
            collapsedGroupIds: Set(sidebarCache.collapsedGroups.map(\.rawValue)),
            isFiltering: !query.isEmpty,
            trigger: trigger,
            worktreeEnrichmentSnapshot: worktreeEnrichmentSnapshot,
            pullRequestFactsSnapshot: Self.pullRequestFactsSnapshot(
                for: worktreeEnrichmentSnapshot,
                repoCache: repoCache
            ),
            paneRowFactsByPaneId: groupingMode == .repo
                ? [:]
                : paneRowFactsByPaneId(now: referenceDate),
            tabGroupFactsByTabId: groupingMode == .tab ? tabGroupFactsByTabId() : [:],
            unavailablePullRequestRepoIds: repositoryIDs.filter {
                repoCache.isPullRequestDataUnavailable(forRepository: $0)
            },
            loadingPullRequestRepoIds: repositoryIDs.filter {
                repoCache.isPullRequestLoading(forRepository: $0)
            }
        )
    }

    static func worktreeEnrichmentSnapshot(
        for worktreeIDs: [UUID],
        repoCache: RepoCacheAtom
    ) -> [UUID: WorktreeEnrichment] {
        var enrichmentByWorktreeID: [UUID: WorktreeEnrichment] = [:]
        enrichmentByWorktreeID.reserveCapacity(worktreeIDs.count)
        for worktreeID in worktreeIDs {
            enrichmentByWorktreeID[worktreeID] = repoCache.worktreeEnrichment(for: worktreeID)
        }
        return enrichmentByWorktreeID
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

    private func sidebarRepos() -> [RepoPresentationItem] {
        store.repositoryTopologyAtom.repositoryIdsInOrder.compactMap { repositoryID in
            guard
                let repository = store.repositoryTopologyAtom.repo(repositoryID),
                let stableKey = store.repositoryTopologyAtom.repositoryStableKey(for: repositoryID)
            else { return nil }
            return RepoPresentationItem(
                repo: repository,
                stableKey: stableKey,
                worktreeStableKeysByID: store.repositoryTopologyAtom.worktreeStableKeysByID
            )
        }
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
        let paneLocationsByWorktreeId = coreAtoms.workspaceLookup.paneLocationsByWorktreeId(
            repositoryTopology: store.repositoryTopologyAtom,
            workspacePane: store.paneAtom,
            workspaceTab: workspaceTab,
            declaredWorktreeIDs: Set(repos.flatMap(\.worktrees).map(\.id))
        )
        let associatedPaneIDs = Set(paneLocationsByWorktreeId.values.flatMap { $0 }.map(\.paneId))
        let unassociatedPaneLocations = Self.unassociatedPaneLocations(
            repositoryTopology: store.repositoryTopologyAtom,
            workspacePane: store.paneAtom,
            workspaceTab: workspaceTab,
            associatedPaneIDs: associatedPaneIDs
        )
        return RepoExplorerSnapshot(
            repos: repos,
            repoEnrichmentByRepoId: repoEnrichmentByRepoId,
            groupingMode: groupingMode,
            sortOrder: sortOrder,
            query: query,
            paneLocationsByWorktreeId: paneLocationsByWorktreeId,
            unassociatedPaneLocations: unassociatedPaneLocations,
            bridgePaneCommandCandidatesByWorktreeId: bridgePaneCommandCandidatesByWorktreeId(
                paneLocationsByWorktreeId: paneLocationsByWorktreeId
            )
        )
    }

    private static func unassociatedPaneLocations(
        repositoryTopology: RepositoryTopologyAtom,
        workspacePane: WorkspacePaneAtom,
        workspaceTab: WorkspaceTabLayoutDerived,
        associatedPaneIDs: Set<UUID>
    ) -> [WorkspacePaneLocation] {
        var locations: [WorkspacePaneLocation] = []
        var seenPaneIDs = Set<UUID>()
        for (tabIndex, tab) in workspaceTab.tabs.enumerated() {
            for paneID in tab.allPaneIds {
                guard seenPaneIDs.insert(paneID).inserted, !associatedPaneIDs.contains(paneID),
                    let paneFacts = workspacePane.graphAtom.paneStructuralFacts(paneID),
                    paneFacts.residency == .active,
                    repositoryTopology.validatedAssociation(
                        repoId: paneFacts.repoID,
                        worktreeId: paneFacts.worktreeID
                    ) == nil
                else { continue }
                locations.append(
                    WorkspacePaneLocation(
                        paneId: paneID,
                        tabId: tab.id,
                        tabIndex: tabIndex,
                        paneIndexInTab: tab.activePaneIds.firstIndex(of: paneID)
                            ?? tab.allPaneIds.firstIndex(of: paneID)
                            ?? 0,
                        isActiveInTab: tab.activePaneId == paneID
                    )
                )
            }
        }
        return locations
    }

    func bridgePaneCommandCandidatesByWorktreeId(
        paneLocationsByWorktreeId: [UUID: [WorkspacePaneLocation]]
    ) -> [UUID: [BridgePaneCommandCandidate]] {
        let paneGraph = store.paneAtom.graphAtom
        let activeTabID = store.tabLayoutAtom.activeTabId
        let activePaneID = activeTabID.flatMap { store.tabLayoutAtom.tab($0)?.activePaneId }
        var candidatesByWorktreeID: [UUID: [BridgePaneCommandCandidate]] = [:]
        for (worktreeID, paneLocations) in paneLocationsByWorktreeId {
            candidatesByWorktreeID[worktreeID] = paneLocations.compactMap { location in
                guard let paneFacts = paneGraph.paneStructuralFacts(location.paneId) else { return nil }
                return BridgePaneCommandCandidate(
                    paneId: paneFacts.paneID,
                    worktreeId: worktreeID,
                    isBridgePane: paneFacts.isBridgeEligible,
                    isPaneActive: paneFacts.residency == .active,
                    isCurrentActivePane: activeTabID == location.tabId && activePaneID == paneFacts.paneID,
                    attendanceOrdinal: bridgeAttendanceSnapshot(paneFacts.paneID),
                    tabIndex: location.tabIndex,
                    paneIndexInTab: location.paneIndexInTab
                )
            }
        }
        return candidatesByWorktreeID
    }

    private func paneRowFactsByPaneId(now: Date) -> [UUID: RepoExplorerPaneRowFacts] {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        let recentPaneInteractions =
            coreAtoms.workspaceEntityRecency.recentEntities.compactMap { recency -> (UUID, Date)? in
                guard case .pane(let paneID) = recency.entity else { return nil }
                return (paneID, recency.lastInteractedAt)
            }
        let lastInteractionByPaneID: [UUID: Date] = Dictionary(
            uniqueKeysWithValues: recentPaneInteractions
        )
        let routingContext = KeyboardRoutingContext.current(
            windowLifecycle: coreAtoms.windowLifecycle,
            managementLayer: coreAtoms.managementLayer,
            uiState: sidebarState,
            commandBarSurface: coreAtoms.commandBarSurface,
            transientKeyboardSurface: coreAtoms.transientKeyboardSurface
        )
        let focusedPaneID =
            routingContext.isStableMainWindowChain
            ? coreAtoms.attendedPane.attendedPaneId
            : nil
        let allPaneIDs = workspaceTab.tabs.flatMap(\.allPaneIds)
        let facts: [UUID: RepoExplorerPaneRowFacts] = Dictionary(
            uniqueKeysWithValues: allPaneIDs.compactMap { paneID -> (UUID, RepoExplorerPaneRowFacts)? in
                guard let pane = store.paneAtom.pane(paneID) else { return nil }
                let terminalTitle = paneDisplayTitleCache.resolve(
                    paneId: paneID,
                    liveTitle: pane.title,
                    cwd: pane.metadata.facets.cwd,
                    shellExecutablePath: pane.metadata.contentType == .terminal
                        ? SessionConfiguration.defaultShell()
                        : nil
                )
                let referenceDate = lastInteractionByPaneID[paneID] ?? pane.metadata.createdAt
                return (
                    paneID,
                    RepoExplorerPaneRowFacts(
                        terminalTitle: terminalTitle,
                        noteText: pane.metadata.note,
                        latestMessageText: latestPaneMessageSnapshot(paneID),
                        recencyReferenceDate: referenceDate,
                        recencyText: RepoExplorerPaneRecencyText.display(
                            lastInteractedAt: referenceDate,
                            now: now
                        ),
                        recencyTier: RepoExplorerPaneRecencyTier.classify(
                            referenceDate: referenceDate,
                            now: now
                        ),
                        isActive: paneID == focusedPaneID,
                        isDrawerPane: store.paneAtom.graphAtom.paneState(paneID)?.isDrawerChild == true
                    )
                )
            }
        )
        paneDisplayTitleCache.retainOnly(paneIds: Set(allPaneIDs))
        return facts
    }

    private func tabGroupFactsByTabId() -> [UUID: RepoExplorerTabGroupFacts] {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        return Dictionary(
            uniqueKeysWithValues: workspaceTab.tabs.map { tab in
                (
                    tab.id,
                    RepoExplorerTabGroupFacts(
                        displayTitle: coreAtoms.tabDisplay.displayTitle(
                            for: tab,
                            workspacePane: store.paneAtom,
                            workspaceRepositoryTopology: store.repositoryTopologyAtom,
                            repoCache: repoCache
                        )
                    )
                )
            }
        )
    }
}
