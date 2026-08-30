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
    private(set) var fullCaptureCount = 0
    var presentationCaptureCount = 0
    var scopedCaptureCount = 0
    private(set) var paneFactCaptureCount = 0

    var isRepoSurfaceVisible: Bool {
        sidebarState.sidebarSurface == .repos
    }

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
        fullCaptureCount += 1
        let repos = sidebarRepos()
        let worktreeEnrichmentSnapshot = Self.worktreeEnrichmentSnapshot(
            for: repos.flatMap(\.worktrees).map(\.id),
            repoCache: repoCache
        )
        let groupingMode = preferences.groupingMode
        let repositoryIDs = Set(repos.map(\.id))
        let repositoryActivityInputs = captureRepositoryActivityInputs(
            for: repos,
            groupingMode: groupingMode
        )
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
            },
            localActivityHydrationDisposition: repositoryActivityInputs.hydrationDisposition,
            repositoryLocalActivityByStableKey: repositoryActivityInputs.activityByStableKey,
            repositoryFactUpdateProgressByRepoId: Dictionary(
                uniqueKeysWithValues: repos.compactMap { repository in
                    repoCache.repositoryFactUpdateProgress(for: repository.id).map {
                        (repository.id, $0)
                    }
                }
            ),
            activityReferenceDate: referenceDate
        )
    }

    func capturePresentationRequest(
        previous: RepoExplorerProjectionRequest,
        query: String,
        referenceDate: Date
    ) -> RepoExplorerProjectionRequest {
        presentationCaptureCount += 1
        let groupingMode = preferences.groupingMode
        let sortOrder = groupingMode == .tab ? previous.snapshot.sortOrder : preferences.sortOrder
        let groupingChanged = groupingMode != previous.snapshot.groupingMode
        let repositoryActivityInputs =
            groupingChanged
            ? captureRepositoryActivityInputs(
                for: previous.snapshot.repos,
                groupingMode: groupingMode
            )
            : (
                hydrationDisposition: previous.localActivityHydrationDisposition,
                activityByStableKey: previous.repositoryLocalActivityByStableKey
            )
        let paneFacts: [UUID: RepoExplorerPaneRowFacts]
        let tabFacts: [UUID: RepoExplorerTabGroupFacts]
        if groupingChanged {
            let paneIDs = demandedPaneIDs(in: previous.snapshot)
            let tabIDs = demandedTabIDs(in: previous.snapshot)
            paneFacts =
                groupingMode == .repo
                ? [:]
                : Dictionary(
                    uniqueKeysWithValues: paneIDs.compactMap { paneID in
                        capturePaneFact(paneID: paneID, now: referenceDate).map { (paneID, $0) }
                    }
                )
            tabFacts =
                groupingMode == .tab
                ? Dictionary(
                    uniqueKeysWithValues: tabIDs.compactMap { tabID in
                        captureTabFact(tabID: tabID).map { (tabID, $0) }
                    }
                )
                : [:]
        } else {
            paneFacts = previous.paneRowFactsByPaneId
            tabFacts = previous.tabGroupFactsByTabId
        }
        return previous.replacing(
            snapshot: previous.snapshot.replacing(
                groupingMode: groupingMode,
                sortOrder: sortOrder,
                query: query
            ),
            collapsedGroupIds: Set(sidebarCache.collapsedGroups.map(\.rawValue)),
            isFiltering: !query.isEmpty,
            paneRowFactsByPaneId: paneFacts,
            tabGroupFactsByTabId: tabFacts,
            localActivityHydrationDisposition: repositoryActivityInputs.hydrationDisposition,
            repositoryLocalActivityByStableKey: repositoryActivityInputs.activityByStableKey,
            activityReferenceDate: groupingChanged ? referenceDate : previous.activityReferenceDate
        )
    }

    func captureScoped(
        _ invalidation: RepoExplorerInputInvalidation,
        previous: RepoExplorerProjectionRequest,
        referenceDate: Date
    ) -> RepoExplorerScopedCapture? {
        scopedCaptureCount += 1
        switch invalidation {
        case .structural, .presentation, .activityHydration:
            return nil
        case .repositoryActivity(let repositoryID):
            return captureRepositoryActivity(
                repositoryID,
                previous: previous,
                referenceDate: referenceDate
            )
        case .repository(let repositoryID):
            return captureRepositoryChange(repositoryID, previous: previous)
        case .worktree(let worktreeID):
            return captureWorktreeChange(worktreeID, previous: previous)
        case .pane(let paneID):
            return capturePaneChanges([paneID], previous: previous, referenceDate: referenceDate)
        case .tab(let tabID):
            guard previous.snapshot.groupingMode == .tab,
                let fact = captureTabFact(tabID: tabID),
                previous.tabGroupFactsByTabId[tabID] != fact
            else { return unchangedScopedCapture(previous) }
            var tabFacts = previous.tabGroupFactsByTabId
            tabFacts[tabID] = fact
            return RepoExplorerScopedCapture(
                request: previous.replacing(tabGroupFactsByTabId: tabFacts),
                changes: [.tab(tabID)],
                requiresFullProjection: false
            )
        case .attention:
            let previousFocusedPaneIDs = Set(
                previous.paneRowFactsByPaneId.compactMap { paneID, facts in facts.isActive ? paneID : nil }
            )
            let nextFocusedPaneID = focusedPaneID()
            let affectedPaneIDs = previousFocusedPaneIDs.union(nextFocusedPaneID.map { [$0] } ?? [])
            return capturePaneChanges(
                affectedPaneIDs,
                previous: previous,
                referenceDate: referenceDate
            )
        }
    }

    private func captureRepositoryActivity(
        _ repositoryID: UUID,
        previous: RepoExplorerProjectionRequest,
        referenceDate: Date
    ) -> RepoExplorerScopedCapture? {
        guard previous.snapshot.groupingMode == .repo,
            let repositoryStableKey = store.repositoryTopologyAtom.repositoryStableKey(
                for: repositoryID
            )
        else { return unchangedScopedCapture(previous) }
        var activityByRepositoryStableKey = previous.repositoryLocalActivityByStableKey
        activityByRepositoryStableKey[repositoryStableKey] =
            coreAtoms.repositoryLocalActivity.activity(for: repositoryStableKey)
        return RepoExplorerScopedCapture(
            request: previous.replacing(
                repositoryLocalActivityByStableKey: activityByRepositoryStableKey,
                activityReferenceDate: referenceDate
            ),
            changes: [.repositoryActivity(repositoryID)],
            requiresFullProjection: false
        )
    }

    private func captureRepositoryActivityInputs(
        for repositories: [RepoPresentationItem],
        groupingMode: RepoExplorerGroupingMode
    ) -> (
        hydrationDisposition: RepositoryLocalActivityHydrationDisposition,
        activityByStableKey: [String: RepositoryLocalActivity]
    ) {
        guard groupingMode == .repo else { return (.pending, [:]) }
        let repositoryLocalActivity = coreAtoms.repositoryLocalActivity
        return (
            repositoryLocalActivity.hydrationDisposition,
            Dictionary(
                uniqueKeysWithValues: repositories.compactMap { repository in
                    repositoryLocalActivity.activity(for: repository.stableKey).map {
                        (repository.stableKey, $0)
                    }
                }
            )
        )
    }

    private func captureRepositoryChange(
        _ repositoryID: UUID,
        previous: RepoExplorerProjectionRequest
    ) -> RepoExplorerScopedCapture? {
        guard let repositoryIndex = previous.snapshot.repos.firstIndex(where: { $0.id == repositoryID }),
            let repository = store.repositoryTopologyAtom.repo(repositoryID),
            let stableKey = store.repositoryTopologyAtom.repositoryStableKey(for: repositoryID)
        else { return nil }
        let previousRepository = previous.snapshot.repos[repositoryIndex]
        let updatedRepository = RepoPresentationItem(
            repo: repository,
            stableKey: stableKey,
            worktreeStableKeysByID: store.repositoryTopologyAtom.worktreeStableKeysByID
        )
        guard previousRepository.worktrees.map(\.id) == updatedRepository.worktrees.map(\.id) else { return nil }

        var repositories = previous.snapshot.repos
        repositories[repositoryIndex] = updatedRepository
        var repoEnrichment = previous.snapshot.repoEnrichmentSnapshotByRepoId
        let previousRepoEnrichment = repoEnrichment[repositoryID]
        repoEnrichment[repositoryID] = repoCache.repoEnrichment(for: repositoryID)
        let request = captureRepositoryRuntimeFacts(
            repositoryID,
            worktreeIDs: updatedRepository.worktrees.map(\.id),
            previous: previous.replacing(
                snapshot: previous.snapshot.replacing(
                    repos: repositories,
                    repoEnrichmentByRepoId: repoEnrichment
                )
            )
        )
        let repositoryPresentationChanged = previousRepository != updatedRepository
        let repoEnrichmentChanged = previousRepoEnrichment != repoEnrichment[repositoryID]
        let progressChanged =
            previous.repositoryFactUpdateProgressByRepoId[repositoryID]
            != request.repositoryFactUpdateProgressByRepoId[repositoryID]
        let worktreeChanges = Set(
            updatedRepository.worktrees.map { RepoExplorerScopedProjectionChange.worktreeFact($0.id) })
        let changes = worktreeChanges.union(
            repositoryPresentationChanged || progressChanged ? [.repo(repositoryID)] : []
        )
        return RepoExplorerScopedCapture(
            request: request,
            changes: changes,
            requiresFullProjection: repoEnrichmentChanged
        )
    }

    private func captureWorktreeChange(
        _ worktreeID: UUID,
        previous: RepoExplorerProjectionRequest
    ) -> RepoExplorerScopedCapture? {
        guard
            let repository = previous.snapshot.repos.first(where: { repo in
                repo.worktrees.contains(where: { $0.id == worktreeID })
            })
        else { return nil }
        let request = captureRepositoryRuntimeFacts(
            repository.id,
            worktreeIDs: [worktreeID],
            previous: previous
        )
        return RepoExplorerScopedCapture(
            request: request,
            changes: request == previous ? [] : [.worktreeFact(worktreeID)],
            requiresFullProjection: false
        )
    }

    private func captureRepositoryRuntimeFacts(
        _ repositoryID: UUID,
        worktreeIDs: [UUID],
        previous: RepoExplorerProjectionRequest
    ) -> RepoExplorerProjectionRequest {
        var worktreeEnrichment = previous.worktreeEnrichmentSnapshot
        for worktreeID in worktreeIDs {
            worktreeEnrichment[worktreeID] = repoCache.worktreeEnrichment(for: worktreeID)
        }
        var pullRequestFacts = previous.pullRequestFactsSnapshot.filter { $0.key.repoId != repositoryID }
        for enrichment in worktreeEnrichment.values where enrichment.repoId == repositoryID {
            guard let branchKey = RepoBranchKey(repoId: repositoryID, branch: enrichment.branch),
                let facts = repoCache.pullRequestFacts(for: branchKey)
            else { continue }
            pullRequestFacts[branchKey] = facts
        }
        var unavailableRepositories = previous.unavailablePullRequestRepoIds
        var loadingRepositories = previous.loadingPullRequestRepoIds
        var progressByRepositoryID = previous.repositoryFactUpdateProgressByRepoId
        if repoCache.isPullRequestDataUnavailable(forRepository: repositoryID) {
            unavailableRepositories.insert(repositoryID)
        } else {
            unavailableRepositories.remove(repositoryID)
        }
        if repoCache.isPullRequestLoading(forRepository: repositoryID) {
            loadingRepositories.insert(repositoryID)
        } else {
            loadingRepositories.remove(repositoryID)
        }
        progressByRepositoryID[repositoryID] = repoCache.repositoryFactUpdateProgress(for: repositoryID)
        return previous.replacing(
            worktreeEnrichmentSnapshot: worktreeEnrichment,
            pullRequestFactsSnapshot: pullRequestFacts,
            unavailablePullRequestRepoIds: unavailableRepositories,
            loadingPullRequestRepoIds: loadingRepositories,
            repositoryFactUpdateProgressByRepoId: progressByRepositoryID
        )
    }

    private func capturePaneChanges(
        _ paneIDs: Set<UUID>,
        previous: RepoExplorerProjectionRequest,
        referenceDate: Date
    ) -> RepoExplorerScopedCapture {
        guard previous.snapshot.groupingMode != .repo else { return unchangedScopedCapture(previous) }
        var paneFacts = previous.paneRowFactsByPaneId
        var bridgeCandidates = previous.snapshot.bridgePaneCommandCandidatesByWorktreeId
        var changes = Set<RepoExplorerScopedProjectionChange>()
        for paneID in paneIDs where paneFacts[paneID] != nil {
            let nextFact = capturePaneFact(paneID: paneID, now: referenceDate)
            if paneFacts[paneID] != nextFact {
                paneFacts[paneID] = nextFact
                changes.insert(.pane(paneID))
            }
            for (worktreeID, locations) in previous.snapshot.paneLocationsByWorktreeId
            where locations.contains(where: { $0.paneId == paneID }) {
                let nextCandidates = bridgePaneCommandCandidatesByWorktreeId(
                    paneLocationsByWorktreeId: [worktreeID: locations]
                )[worktreeID, default: []]
                if bridgeCandidates[worktreeID, default: []] != nextCandidates {
                    bridgeCandidates[worktreeID] = nextCandidates
                    changes.insert(.worktreeFact(worktreeID))
                }
            }
        }
        return RepoExplorerScopedCapture(
            request: previous.replacing(
                snapshot: previous.snapshot.replacing(
                    bridgePaneCommandCandidatesByWorktreeId: bridgeCandidates
                ),
                paneRowFactsByPaneId: paneFacts
            ),
            changes: changes,
            requiresFullProjection: false
        )
    }

    private func unchangedScopedCapture(
        _ previous: RepoExplorerProjectionRequest
    ) -> RepoExplorerScopedCapture {
        RepoExplorerScopedCapture(request: previous, changes: [], requiresFullProjection: false)
    }

    func demandedPaneIDs(in snapshot: RepoExplorerSnapshot) -> Set<UUID> {
        Set(
            snapshot.paneLocationsByWorktreeId.values.flatMap { $0.map(\.paneId) }
                + snapshot.unassociatedPaneLocations.map(\.paneId)
        )
    }

    func demandedTabIDs(in snapshot: RepoExplorerSnapshot) -> Set<UUID> {
        Set(
            snapshot.paneLocationsByWorktreeId.values.flatMap { $0.map(\.tabId) }
                + snapshot.unassociatedPaneLocations.map(\.tabId)
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
        let allPaneIDs = workspaceTab.tabs.flatMap(\.allPaneIds)
        let facts = Dictionary(
            uniqueKeysWithValues: allPaneIDs.compactMap { paneID in
                capturePaneFact(paneID: paneID, now: now).map { (paneID, $0) }
            }
        )
        paneDisplayTitleCache.retainOnly(paneIds: Set(allPaneIDs))
        return facts
    }

    func capturePaneFact(
        paneID: UUID,
        now: Date
    ) -> RepoExplorerPaneRowFacts? {
        paneFactCaptureCount += 1
        guard let pane = store.paneAtom.pane(paneID) else { return nil }
        let terminalTitle = paneDisplayTitleCache.resolve(
            paneId: paneID,
            liveTitle: pane.title,
            cwd: pane.metadata.facets.cwd,
            shellExecutablePath: pane.metadata.contentType == .terminal
                ? SessionConfiguration.defaultShell()
                : nil
        )
        let referenceDate =
            coreAtoms.workspaceEntityRecency
            .recency(for: .pane(paneID: paneID))?.lastInteractedAt
            ?? pane.metadata.createdAt
        return RepoExplorerPaneRowFacts(
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
            isActive: paneID == focusedPaneID(),
            isDrawerPane: store.paneAtom.graphAtom.paneState(paneID)?.isDrawerChild == true
        )
    }

    func focusedPaneID() -> UUID? {
        let routingContext = KeyboardRoutingContext.current(
            windowLifecycle: coreAtoms.windowLifecycle,
            managementLayer: coreAtoms.managementLayer,
            uiState: sidebarState,
            commandBarSurface: coreAtoms.commandBarSurface,
            transientKeyboardSurface: coreAtoms.transientKeyboardSurface
        )
        return routingContext.isStableMainWindowChain
            ? coreAtoms.attendedPane.attendedPaneId
            : nil
    }

    private func tabGroupFactsByTabId() -> [UUID: RepoExplorerTabGroupFacts] {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        return Dictionary(
            uniqueKeysWithValues: workspaceTab.tabs.compactMap { tab in
                captureTabFact(tabID: tab.id).map { (tab.id, $0) }
            }
        )
    }

    func captureTabFact(tabID: UUID) -> RepoExplorerTabGroupFacts? {
        guard let tab = store.tabLayoutAtom.tab(tabID) else { return nil }
        return RepoExplorerTabGroupFacts(
            displayTitle: coreAtoms.tabDisplay.displayTitle(
                for: tab,
                workspacePane: store.paneAtom,
                workspaceRepositoryTopology: store.repositoryTopologyAtom,
                repoCache: repoCache
            )
        )
    }
}
