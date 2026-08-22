import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Foundation

enum RepoExplorerScopedProjectionChange: Equatable, Hashable, Sendable {
    case repo(UUID)
    case worktreeFact(UUID)
    case pane(UUID)
    case tab(UUID)
}

struct RepoExplorerProjectionDelta: Equatable, Sendable {
    let baselineRevision: Int
    let baselineResult: RepoExplorerProjectionResult
    let targetRequest: RepoExplorerProjectionRequest
    let changes: Set<RepoExplorerScopedProjectionChange>
}

enum RepoExplorerProjectionWork: Equatable, Sendable {
    case full(RepoExplorerProjectionRequest)
    case delta(RepoExplorerProjectionDelta)

    var generation: Int {
        targetRequest.generation
    }

    var targetRequest: RepoExplorerProjectionRequest {
        switch self {
        case .full(let request): request
        case .delta(let delta): delta.targetRequest
        }
    }

    static func combinePending(
        _ pending: Self,
        _ latest: Self
    ) -> Self {
        guard case .delta(let pendingDelta) = pending,
            case .delta(let latestDelta) = latest,
            pendingDelta.baselineRevision == latestDelta.baselineRevision,
            pendingDelta.baselineResult == latestDelta.baselineResult
        else {
            return .full(latest.targetRequest)
        }
        return .delta(
            RepoExplorerProjectionDelta(
                baselineRevision: latestDelta.baselineRevision,
                baselineResult: latestDelta.baselineResult,
                targetRequest: latestDelta.targetRequest,
                changes: pendingDelta.changes.union(latestDelta.changes)
            )
        )
    }
}

struct RepoExplorerProjectionRequest: Equatable, Sendable {
    let generation: Int
    let snapshot: RepoExplorerSnapshot
    let collapsedGroupIds: Set<String>
    let isFiltering: Bool
    let trigger: AppPolicies.SidebarProjection.Trigger
    let worktreeEnrichmentSnapshot: [UUID: WorktreeEnrichment]
    let pullRequestFactsSnapshot: [RepoBranchKey: PullRequestFacts]
    let paneRowFactsByPaneId: [UUID: RepoExplorerPaneRowFacts]
    let tabGroupFactsByTabId: [UUID: RepoExplorerTabGroupFacts]
    /// Repos whose pull request data has resolved to a terminal absence (no remote, or provider
    /// failures past the forge honesty threshold). This is independent of
    /// `pullRequestFactsSnapshot`: a repo can transition into this set with zero change to its
    /// (empty) facts snapshot, so every equality/admission check below must compare this field
    /// explicitly — otherwise that transition compares equal and silently skips re-projection.
    let unavailablePullRequestRepoIds: Set<UUID>
    let loadingPullRequestRepoIds: Set<UUID>

    init(
        generation: Int,
        snapshot: RepoExplorerSnapshot,
        collapsedGroupIds: Set<String>,
        isFiltering: Bool,
        trigger: AppPolicies.SidebarProjection.Trigger,
        worktreeEnrichmentSnapshot: [UUID: WorktreeEnrichment] = [:],
        pullRequestFactsSnapshot: [RepoBranchKey: PullRequestFacts] = [:],
        paneRowFactsByPaneId: [UUID: RepoExplorerPaneRowFacts] = [:],
        tabGroupFactsByTabId: [UUID: RepoExplorerTabGroupFacts] = [:],
        unavailablePullRequestRepoIds: Set<UUID> = [],
        loadingPullRequestRepoIds: Set<UUID> = []
    ) {
        self.generation = generation
        self.snapshot = snapshot
        self.collapsedGroupIds = collapsedGroupIds
        self.isFiltering = isFiltering
        self.trigger = trigger
        self.worktreeEnrichmentSnapshot = worktreeEnrichmentSnapshot
        self.pullRequestFactsSnapshot = pullRequestFactsSnapshot
        self.paneRowFactsByPaneId = paneRowFactsByPaneId
        self.tabGroupFactsByTabId = tabGroupFactsByTabId
        self.unavailablePullRequestRepoIds = unavailablePullRequestRepoIds
        self.loadingPullRequestRepoIds = loadingPullRequestRepoIds
    }

    func generated(
        generation: Int,
        trigger: AppPolicies.SidebarProjection.Trigger
    ) -> Self {
        Self(
            generation: generation,
            snapshot: snapshot,
            collapsedGroupIds: collapsedGroupIds,
            isFiltering: isFiltering,
            trigger: trigger,
            worktreeEnrichmentSnapshot: worktreeEnrichmentSnapshot,
            pullRequestFactsSnapshot: pullRequestFactsSnapshot,
            paneRowFactsByPaneId: paneRowFactsByPaneId,
            tabGroupFactsByTabId: tabGroupFactsByTabId,
            unavailablePullRequestRepoIds: unavailablePullRequestRepoIds,
            loadingPullRequestRepoIds: loadingPullRequestRepoIds
        )
    }

    func replacing(
        snapshot: RepoExplorerSnapshot? = nil,
        collapsedGroupIds: Set<String>? = nil,
        isFiltering: Bool? = nil,
        worktreeEnrichmentSnapshot: [UUID: WorktreeEnrichment]? = nil,
        pullRequestFactsSnapshot: [RepoBranchKey: PullRequestFacts]? = nil,
        paneRowFactsByPaneId: [UUID: RepoExplorerPaneRowFacts]? = nil,
        tabGroupFactsByTabId: [UUID: RepoExplorerTabGroupFacts]? = nil,
        unavailablePullRequestRepoIds: Set<UUID>? = nil,
        loadingPullRequestRepoIds: Set<UUID>? = nil
    ) -> Self {
        Self(
            generation: generation,
            snapshot: snapshot ?? self.snapshot,
            collapsedGroupIds: collapsedGroupIds ?? self.collapsedGroupIds,
            isFiltering: isFiltering ?? self.isFiltering,
            trigger: trigger,
            worktreeEnrichmentSnapshot: worktreeEnrichmentSnapshot ?? self.worktreeEnrichmentSnapshot,
            pullRequestFactsSnapshot: pullRequestFactsSnapshot ?? self.pullRequestFactsSnapshot,
            paneRowFactsByPaneId: paneRowFactsByPaneId ?? self.paneRowFactsByPaneId,
            tabGroupFactsByTabId: tabGroupFactsByTabId ?? self.tabGroupFactsByTabId,
            unavailablePullRequestRepoIds: unavailablePullRequestRepoIds
                ?? self.unavailablePullRequestRepoIds,
            loadingPullRequestRepoIds: loadingPullRequestRepoIds ?? self.loadingPullRequestRepoIds
        )
    }

    func scopedChange(from previous: Self) -> RepoExplorerScopedProjectionChange? {
        guard snapshot.groupingMode == .repo,
            previous.snapshot.groupingMode == snapshot.groupingMode,
            previous.snapshot.sortOrder == snapshot.sortOrder,
            previous.snapshot.query == snapshot.query,
            previous.snapshot.repoEnrichmentSnapshotByRepoId == snapshot.repoEnrichmentSnapshotByRepoId,
            previous.snapshot.paneLocationsByWorktreeId == snapshot.paneLocationsByWorktreeId,
            previous.snapshot.unassociatedPaneLocations == snapshot.unassociatedPaneLocations,
            previous.snapshot.bridgePaneCommandCandidatesByWorktreeId
                == snapshot.bridgePaneCommandCandidatesByWorktreeId,
            previous.collapsedGroupIds == collapsedGroupIds,
            previous.isFiltering == isFiltering,
            previous.unavailablePullRequestRepoIds == unavailablePullRequestRepoIds,
            previous.loadingPullRequestRepoIds == loadingPullRequestRepoIds,
            previous.pullRequestFactsSnapshot == pullRequestFactsSnapshot
                && previous.paneRowFactsByPaneId == paneRowFactsByPaneId
                && previous.tabGroupFactsByTabId == tabGroupFactsByTabId
        else { return nil }

        if previous.snapshot.repos == snapshot.repos {
            let changedWorktreeIds = Set(previous.worktreeEnrichmentSnapshot.keys)
                .union(worktreeEnrichmentSnapshot.keys)
                .filter {
                    previous.worktreeEnrichmentSnapshot[$0] != worktreeEnrichmentSnapshot[$0]
                }
            return changedWorktreeIds.count == 1
                ? changedWorktreeIds.first.map(RepoExplorerScopedProjectionChange.worktreeFact)
                : nil
        }

        guard previous.worktreeEnrichmentSnapshot == worktreeEnrichmentSnapshot,
            previous.snapshot.repos.count == snapshot.repos.count
        else { return nil }
        let changedRepos = zip(previous.snapshot.repos, snapshot.repos).filter { before, after in
            before != after
        }
        guard changedRepos.count == 1,
            Self.differsOnlyByFavorite(changedRepos[0].0, changedRepos[0].1)
        else { return nil }
        return .repo(changedRepos[0].1.id)
    }

    func hasMembershipChange(from previous: Self) -> Bool {
        snapshot.repos.map(\.id) != previous.snapshot.repos.map(\.id)
            || snapshot.repos.flatMap(\.worktrees).map(\.id)
                != previous.snapshot.repos.flatMap(\.worktrees).map(\.id)
    }

    private static func differsOnlyByFavorite(
        _ before: RepoPresentationItem,
        _ after: RepoPresentationItem
    ) -> Bool {
        before.id == after.id
            && before.name == after.name
            && before.repoPath == after.repoPath
            && before.stableKey == after.stableKey
            && before.note == after.note
            && before.tags == after.tags
            && before.worktrees == after.worktrees
            && before.isFavorite != after.isFavorite
    }
}

struct RepoExplorerProjectionResult: Equatable, Sendable {
    let generation: Int
    let snapshot: RepoExplorerSnapshot
    let collapsedGroupIds: Set<String>
    let isFiltering: Bool
    let trigger: AppPolicies.SidebarProjection.Trigger
    let projection: RepoExplorerSidebarProjection
    let rowIndex: RepoExplorerRowIndex
    let workerDuration: Duration
    let projectionDuration: Duration
    let rowIndexDuration: Duration
    let branchStatusByWorktreeId: [UUID: GitBranchStatus]
    let branchNameByWorktreeId: [UUID: String]
    let bridgeCommandResolutionByWorktreeId: [UUID: BridgePaneCommandResolution]
    let paneRowFactsByPaneId: [UUID: RepoExplorerPaneRowFacts]
    let tabGroupFactsByTabId: [UUID: RepoExplorerTabGroupFacts]
    let baselineRevision: Int?

    static let empty: Self = {
        let snapshot = RepoExplorerSnapshot(
            repos: [],
            repoEnrichmentByRepoId: [:],
            groupingMode: .repo,
            sortOrder: .default,
            query: ""
        )
        let projection = RepoExplorerSidebarProjection(
            sections: [],
            resolvedGroups: [],
            loadingRepos: [],
            showsNoResults: false
        )
        return Self(
            generation: 0,
            snapshot: snapshot,
            collapsedGroupIds: [],
            isFiltering: false,
            trigger: .startupDiagnostic,
            projection: projection,
            rowIndex: RepoExplorerRowIndex(
                projection: projection,
                collapsedGroupIds: [],
                isFiltering: false
            ),
            workerDuration: .zero,
            projectionDuration: .zero,
            rowIndexDuration: .zero,
            branchStatusByWorktreeId: [:],
            branchNameByWorktreeId: [:],
            bridgeCommandResolutionByWorktreeId: [:],
            paneRowFactsByPaneId: [:],
            tabGroupFactsByTabId: [:],
            baselineRevision: nil
        )
    }()
}

actor RepoExplorerProjectionWorker {
    static func project(
        _ work: RepoExplorerProjectionWork
    ) throws -> RepoExplorerProjectionResult {
        switch work {
        case .full(let request):
            return try project(request)
        case .delta(let delta):
            var result = delta.baselineResult
            let repositoryChanges = delta.changes.compactMap { change -> UUID? in
                guard case .repo(let repositoryID) = change else { return nil }
                return repositoryID
            }
            .sorted { $0.uuidString < $1.uuidString }
            let worktreeChanges = delta.changes.compactMap { change -> UUID? in
                guard case .worktreeFact(let worktreeID) = change else { return nil }
                return worktreeID
            }
            .sorted { $0.uuidString < $1.uuidString }
            let paneChanges = delta.changes.compactMap { change -> UUID? in
                guard case .pane(let paneID) = change else { return nil }
                return paneID
            }
            .sorted { $0.uuidString < $1.uuidString }
            let tabChanges = delta.changes.compactMap { change -> UUID? in
                guard case .tab(let tabID) = change else { return nil }
                return tabID
            }
            .sorted { $0.uuidString < $1.uuidString }

            for repositoryID in repositoryChanges {
                try Task.checkCancellation()
                guard
                    let updated = applyScopedRepoChange(
                        repoId: repositoryID,
                        request: delta.targetRequest,
                        previous: result
                    )
                else {
                    return try project(delta.targetRequest)
                }
                result = updated
            }
            for worktreeID in worktreeChanges {
                try Task.checkCancellation()
                guard
                    let updated = applyScopedWorktreeFactChange(
                        worktreeId: worktreeID,
                        request: delta.targetRequest,
                        previous: result
                    )
                else {
                    return try project(delta.targetRequest)
                }
                result = updated
            }
            for paneID in paneChanges {
                try Task.checkCancellation()
                guard
                    let updated = applyScopedPaneChange(
                        paneId: paneID,
                        request: delta.targetRequest,
                        previous: result
                    )
                else {
                    return try project(delta.targetRequest)
                }
                result = updated
            }
            for tabID in tabChanges {
                try Task.checkCancellation()
                guard
                    let updated = applyScopedTabChange(
                        tabId: tabID,
                        request: delta.targetRequest,
                        previous: result
                    )
                else {
                    return try project(delta.targetRequest)
                }
                result = updated
            }
            return result.withBaselineRevision(delta.baselineRevision)
        }
    }

    static func applyScopedChange(
        _ change: RepoExplorerScopedProjectionChange,
        request: RepoExplorerProjectionRequest,
        previous: RepoExplorerProjectionResult
    ) -> RepoExplorerProjectionResult? {
        switch change {
        case .repo(let repoId):
            return applyScopedRepoChange(repoId: repoId, request: request, previous: previous)
        case .worktreeFact(let worktreeId):
            return applyScopedWorktreeFactChange(
                worktreeId: worktreeId,
                request: request,
                previous: previous
            )
        case .pane(let paneId):
            return applyScopedPaneChange(paneId: paneId, request: request, previous: previous)
        case .tab(let tabId):
            return applyScopedTabChange(tabId: tabId, request: request, previous: previous)
        }
    }

    func project(_ request: RepoExplorerProjectionRequest) async throws -> RepoExplorerProjectionResult {
        // Runs CPU-bound sidebar projection outside actor/main-actor isolation; cancellation is forwarded below.
        // swiftlint:disable:next no_task_detached
        let projectionTask = Task.detached(priority: .userInitiated) {
            try Self.project(request)
        }

        return try await withTaskCancellationHandler {
            try await projectionTask.value
        } onCancel: {
            projectionTask.cancel()
        }
    }

    static func project(
        _ request: RepoExplorerProjectionRequest
    ) throws -> RepoExplorerProjectionResult {
        try Task.checkCancellation()
        let clock = ContinuousClock()
        let workerStart = clock.now
        let branchStatusByWorktreeId = try branchStatusByWorktreeId(
            snapshot: request.snapshot,
            worktreeEnrichmentByWorktreeId: request.worktreeEnrichmentSnapshot,
            pullRequestFactsByBranch: request.pullRequestFactsSnapshot,
            loadingPullRequestRepoIds: request.loadingPullRequestRepoIds,
            unavailablePullRequestRepoIds: request.unavailablePullRequestRepoIds,
            cancellationCheck: { try Task.checkCancellation() }
        )
        let branchNameByWorktreeId = try branchNameByWorktreeId(
            snapshot: request.snapshot,
            worktreeEnrichmentByWorktreeId: request.worktreeEnrichmentSnapshot,
            cancellationCheck: { try Task.checkCancellation() }
        )
        let projectionStart = clock.now
        let projection = try RepoExplorerProjection.projectCancellable(
            request.snapshot,
            paneRowFactsByPaneId: request.paneRowFactsByPaneId,
            tabGroupFactsByTabId: request.tabGroupFactsByTabId,
            branchNameByWorktreeId: branchNameByWorktreeId,
            branchStatusByWorktreeId: branchStatusByWorktreeId,
            cancellationCheck: { try Task.checkCancellation() }
        )
        let projectionDuration = projectionStart.duration(to: clock.now)
        try Task.checkCancellation()
        let rowIndexStart = clock.now
        let rowIndex = RepoExplorerRowIndex(
            projection: projection,
            collapsedGroupIds: request.collapsedGroupIds,
            isFiltering: request.isFiltering
        )
        let rowIndexDuration = rowIndexStart.duration(to: clock.now)
        try Task.checkCancellation()
        let bridgeCommandResolutionByWorktreeId = try bridgeCommandResolutionByWorktreeId(
            snapshot: request.snapshot,
            cancellationCheck: { try Task.checkCancellation() }
        )
        try Task.checkCancellation()
        return RepoExplorerProjectionResult(
            generation: request.generation,
            snapshot: request.snapshot,
            collapsedGroupIds: request.collapsedGroupIds,
            isFiltering: request.isFiltering,
            trigger: request.trigger,
            projection: projection,
            rowIndex: rowIndex,
            workerDuration: workerStart.duration(to: clock.now),
            projectionDuration: projectionDuration,
            rowIndexDuration: rowIndexDuration,
            branchStatusByWorktreeId: branchStatusByWorktreeId,
            branchNameByWorktreeId: branchNameByWorktreeId,
            bridgeCommandResolutionByWorktreeId: bridgeCommandResolutionByWorktreeId,
            paneRowFactsByPaneId: request.paneRowFactsByPaneId,
            tabGroupFactsByTabId: request.tabGroupFactsByTabId,
            baselineRevision: nil
        )
    }

    private static func bridgeCommandResolutionByWorktreeId(
        snapshot: RepoExplorerSnapshot,
        cancellationCheck: () throws -> Void
    ) throws -> [UUID: BridgePaneCommandResolution] {
        var resolutionsByWorktreeId: [UUID: BridgePaneCommandResolution] = [:]
        let worktrees = snapshot.repos.flatMap(\.worktrees)
        resolutionsByWorktreeId.reserveCapacity(worktrees.count)
        for (index, worktree) in worktrees.enumerated()
        where resolutionsByWorktreeId[worktree.id] == nil {
            if index.isMultiple(of: 256) { try cancellationCheck() }
            resolutionsByWorktreeId[worktree.id] = BridgePaneCommandResolver.resolve(
                worktreeId: worktree.id,
                candidates: snapshot.bridgePaneCommandCandidatesByWorktreeId[worktree.id, default: []]
            )
        }
        return resolutionsByWorktreeId
    }

    private static func branchStatusByWorktreeId(
        snapshot: RepoExplorerSnapshot,
        worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment],
        pullRequestFactsByBranch: [RepoBranchKey: PullRequestFacts],
        loadingPullRequestRepoIds: Set<UUID>,
        unavailablePullRequestRepoIds: Set<UUID>,
        cancellationCheck: () throws -> Void
    ) throws -> [UUID: GitBranchStatus] {
        let worktreeIds = snapshot.repos.flatMap(\.worktrees).map(\.id)
        var branchStatusByWorktreeId = GitBranchStatus.merge(
            worktreeEnrichmentsByWorktreeId: worktreeEnrichmentByWorktreeId,
            pullRequestFactsByBranch: pullRequestFactsByBranch,
            loadingPullRequestRepoIds: loadingPullRequestRepoIds,
            unavailablePullRequestRepoIds: unavailablePullRequestRepoIds
        )
        branchStatusByWorktreeId.reserveCapacity(max(branchStatusByWorktreeId.count, worktreeIds.count))
        for (index, worktreeId) in worktreeIds.enumerated() where branchStatusByWorktreeId[worktreeId] == nil {
            if index.isMultiple(of: 256) { try cancellationCheck() }
            branchStatusByWorktreeId[worktreeId] = .unknown
        }
        return branchStatusByWorktreeId
    }

    private static func branchNameByWorktreeId(
        snapshot: RepoExplorerSnapshot,
        worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment],
        cancellationCheck: () throws -> Void
    ) throws -> [UUID: String] {
        var branchNames: [UUID: String] = [:]
        for (index, worktree) in snapshot.repos.flatMap(\.worktrees).enumerated() {
            if index.isMultiple(of: 256) { try cancellationCheck() }
            branchNames[worktree.id] = branchName(
                enrichment: worktreeEnrichmentByWorktreeId[worktree.id]
            )
        }
        return branchNames
    }

    private static func branchName(enrichment: WorktreeEnrichment?) -> String {
        guard let enrichment else { return "Unknown branch" }
        let cachedBranch = enrichment.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cachedBranch.isEmpty {
            return cachedBranch
        }

        return "detached HEAD"
    }

    private static func applyScopedRepoChange(
        repoId: UUID,
        request: RepoExplorerProjectionRequest,
        previous: RepoExplorerProjectionResult
    ) -> RepoExplorerProjectionResult? {
        guard request.snapshot.groupingMode == .repo,
            let changedRepo = request.snapshot.repos.first(where: { $0.id == repoId }),
            case .ready(let previousContent) = previous.projection
        else { return nil }

        func replacingRepo(in repo: RepoPresentationItem) -> RepoPresentationItem {
            repo.id == repoId ? changedRepo : repo
        }
        let updatedGroups = previousContent.resolvedGroups
            .map { group in
                RepoPresentationGroup(
                    id: group.id,
                    repoTitle: group.repoTitle,
                    organizationName: group.organizationName,
                    repos: group.repos.map { replacingRepo(in: $0) }
                )
            }
            .sorted { lhs, rhs in
                RepoExplorerProjection.repoGroupPrecedes(
                    lhs,
                    rhs,
                    sortOrder: request.snapshot.sortOrder
                )
            }
        let favoriteGroups = updatedGroups.filter { !$0.repos.isEmpty && $0.repos.allSatisfy(\.isFavorite) }
        let regularGroups = updatedGroups.filter { $0.repos.contains { !$0.isFavorite } }
        let updatedLoadingRepos = RepoExplorerProjection.sortedRepos(
            previousContent.loadingRepos.map { replacingRepo(in: $0) },
            sortOrder: request.snapshot.sortOrder
        )
        let favoriteLoadingRepos = updatedLoadingRepos.filter(\.isFavorite)
        let regularLoadingRepos = updatedLoadingRepos.filter { !$0.isFavorite }
        var sections: [RepoExplorerSidebarSection] = []
        if !favoriteGroups.isEmpty || !favoriteLoadingRepos.isEmpty {
            sections.append(
                RepoExplorerSidebarSection(
                    kind: .favorites,
                    resolvedGroups: favoriteGroups,
                    loadingRepos: favoriteLoadingRepos
                )
            )
        }
        sections.append(
            RepoExplorerSidebarSection(
                kind: .repositories,
                resolvedGroups: regularGroups,
                loadingRepos: regularLoadingRepos
            )
        )
        let updatedRows = previousContent.worktreeRowsByGroupId.mapValues { rows in
            rows.map { row in
                RepoExplorerProjectedWorktreeRow(
                    groupId: row.groupId,
                    repo: replacingRepo(in: row.repo),
                    worktree: row.worktree,
                    rowId: row.rowId,
                    checkoutColorHex: row.checkoutColorHex,
                    placementContext: row.placementContext
                )
            }
        }
        let projection = RepoExplorerSidebarProjection.ready(
            RepoExplorerSidebarContent(
                sections: sections,
                resolvedGroups: sections.flatMap(\.resolvedGroups),
                worktreeRowsByGroupId: updatedRows,
                paneRowsByGroupId: previousContent.paneRowsByGroupId,
                paneDestinationsByWorktreeId: previousContent.paneDestinationsByWorktreeId,
                paneDestinationsByRepoId: previousContent.paneDestinationsByRepoId,
                loadingRepos: sections.flatMap(\.loadingRepos),
                emptyState: previousContent.emptyState
            )
        )
        return scopedResult(request: request, previous: previous, projection: projection)
    }

    private static func applyScopedWorktreeFactChange(
        worktreeId: UUID,
        request: RepoExplorerProjectionRequest,
        previous: RepoExplorerProjectionResult
    ) -> RepoExplorerProjectionResult? {
        guard
            request.snapshot.repos.contains(where: { repo in
                repo.worktrees.contains(where: { $0.id == worktreeId })
            })
        else { return nil }
        var branchStatuses = previous.branchStatusByWorktreeId
        var branchNames = previous.branchNameByWorktreeId
        var bridgeCommandResolutions = previous.bridgeCommandResolutionByWorktreeId
        let enrichment = request.worktreeEnrichmentSnapshot[worktreeId]
        let pullRequestFacts =
            enrichment
            .flatMap { RepoBranchKey(repoId: $0.repoId, branch: $0.branch) }
            .flatMap { request.pullRequestFactsSnapshot[$0] }
        branchStatuses[worktreeId] = GitBranchStatus.status(
            enrichment: enrichment,
            pullRequestFacts: pullRequestFacts,
            pullRequestIsLoading: enrichment.map { request.loadingPullRequestRepoIds.contains($0.repoId) }
                ?? false,
            pullRequestDataUnavailable: enrichment.map { request.unavailablePullRequestRepoIds.contains($0.repoId) }
                ?? false
        )
        branchNames[worktreeId] = branchName(enrichment: enrichment)
        bridgeCommandResolutions[worktreeId] = BridgePaneCommandResolver.resolve(
            worktreeId: worktreeId,
            candidates: request.snapshot.bridgePaneCommandCandidatesByWorktreeId[worktreeId, default: []]
        )
        return RepoExplorerProjectionResult(
            generation: request.generation,
            snapshot: request.snapshot,
            collapsedGroupIds: request.collapsedGroupIds,
            isFiltering: request.isFiltering,
            trigger: request.trigger,
            projection: previous.projection,
            rowIndex: previous.rowIndex,
            workerDuration: .zero,
            projectionDuration: .zero,
            rowIndexDuration: .zero,
            branchStatusByWorktreeId: branchStatuses,
            branchNameByWorktreeId: branchNames,
            bridgeCommandResolutionByWorktreeId: bridgeCommandResolutions,
            paneRowFactsByPaneId: request.paneRowFactsByPaneId,
            tabGroupFactsByTabId: request.tabGroupFactsByTabId,
            baselineRevision: nil
        )
    }

    private static func applyScopedPaneChange(
        paneId: UUID,
        request: RepoExplorerProjectionRequest,
        previous: RepoExplorerProjectionResult
    ) -> RepoExplorerProjectionResult? {
        guard request.snapshot.groupingMode != .repo,
            request.paneRowFactsByPaneId[paneId] != nil,
            case .ready(let previousContent) = previous.projection
        else { return nil }
        var foundAssociatedRow = false
        let updatedPaneRows = previousContent.paneRowsByGroupId.mapValues { rows in
            let updatedRows = rows.map { row in
                guard row.destination.paneId == paneId else { return row }
                foundAssociatedRow = true
                return updatedPaneRow(
                    row,
                    request: request,
                    branchNames: previous.branchNameByWorktreeId,
                    branchStatuses: previous.branchStatusByWorktreeId
                )
            }
            guard foundAssociatedRow else { return updatedRows }
            return updatedRows.sorted { lhs, rhs in
                RepoExplorerProjection.paneRowPrecedes(
                    lhs.destination,
                    rhs.destination,
                    paneRowFactsByPaneId: request.paneRowFactsByPaneId,
                    usesRecency: request.snapshot.groupingMode == .pane
                )
            }
        }
        let isUnassociatedPane = request.snapshot.unassociatedPaneLocations.contains { $0.paneId == paneId }
        guard foundAssociatedRow || isUnassociatedPane else { return nil }
        let projection = RepoExplorerSidebarProjection.ready(
            RepoExplorerSidebarContent(
                sections: previousContent.sections,
                resolvedGroups: previousContent.resolvedGroups,
                worktreeRowsByGroupId: previousContent.worktreeRowsByGroupId,
                paneRowsByGroupId: updatedPaneRows,
                paneDestinationsByWorktreeId: previousContent.paneDestinationsByWorktreeId,
                paneDestinationsByRepoId: previousContent.paneDestinationsByRepoId,
                loadingRepos: previousContent.loadingRepos,
                emptyState: previousContent.emptyState
            )
        )
        return scopedResult(request: request, previous: previous, projection: projection)
    }

    private static func updatedPaneRow(
        _ row: RepoExplorerProjectedPaneRow,
        request: RepoExplorerProjectionRequest,
        branchNames: [UUID: String],
        branchStatuses: [UUID: GitBranchStatus]
    ) -> RepoExplorerProjectedPaneRow {
        let paneFacts = request.paneRowFactsByPaneId[row.destination.paneId]
        let normalizedBranchName = RepoExplorerProjection.normalizedBranchName(
            branchNames[row.destination.worktreeId]
        )
        let branchContextText: String?
        if request.snapshot.groupingMode == .tab {
            branchContextText = normalizedBranchName.map { branchName in
                let repositoryName =
                    request.snapshot.repos
                    .first(where: { $0.id == row.destination.repoId })?.name
                    ?? "Repository"
                return "\(repositoryName) · \(branchName)"
            }
        } else {
            branchContextText = normalizedBranchName
        }
        return RepoExplorerProjectedPaneRow(
            groupId: row.groupId,
            repoId: row.repoId,
            destination: row.destination,
            rowId: row.rowId,
            primaryText: RepoExplorerProjection.panePrimaryText(
                row.destination,
                terminalTitle: paneFacts?.sidebarTerminalTitle
            ),
            secondaryLine: paneFacts?.secondaryLine,
            branchContextText: branchContextText,
            branchStatus: branchStatuses[row.destination.worktreeId],
            recencyText: paneFacts?.recencyText ?? "Now",
            recencyTier: paneFacts?.recencyTier ?? .strongBlue,
            isActive: paneFacts?.isActive ?? false,
            isDrawerPane: paneFacts?.isDrawerPane ?? false
        )
    }

    private static func applyScopedTabChange(
        tabId: UUID,
        request: RepoExplorerProjectionRequest,
        previous: RepoExplorerProjectionResult
    ) -> RepoExplorerProjectionResult? {
        guard request.snapshot.groupingMode == .tab,
            let tabFacts = request.tabGroupFactsByTabId[tabId],
            case .ready(let previousContent) = previous.projection
        else { return nil }
        let groupID = "tab:\(tabId.uuidString)"
        var foundGroup = false
        func updatedGroup(_ group: RepoPresentationGroup) -> RepoPresentationGroup {
            guard group.id == groupID else { return group }
            foundGroup = true
            return RepoPresentationGroup(
                id: group.id,
                repoTitle: tabFacts.displayTitle,
                organizationName: group.organizationName,
                repos: group.repos
            )
        }
        let resolvedGroups = previousContent.resolvedGroups.map(updatedGroup)
        let sections = previousContent.sections.map { section in
            RepoExplorerSidebarSection(
                kind: section.kind,
                resolvedGroups: section.resolvedGroups.map(updatedGroup),
                loadingRepos: section.loadingRepos,
                unassociatedPaneDestinations: section.unassociatedPaneDestinations
            )
        }
        guard foundGroup else { return nil }
        let projection = RepoExplorerSidebarProjection.ready(
            RepoExplorerSidebarContent(
                sections: sections,
                resolvedGroups: resolvedGroups,
                worktreeRowsByGroupId: previousContent.worktreeRowsByGroupId,
                paneRowsByGroupId: previousContent.paneRowsByGroupId,
                paneDestinationsByWorktreeId: previousContent.paneDestinationsByWorktreeId,
                paneDestinationsByRepoId: previousContent.paneDestinationsByRepoId,
                loadingRepos: previousContent.loadingRepos,
                emptyState: previousContent.emptyState
            )
        )
        return scopedResult(request: request, previous: previous, projection: projection)
    }

    private static func scopedResult(
        request: RepoExplorerProjectionRequest,
        previous: RepoExplorerProjectionResult,
        projection: RepoExplorerSidebarProjection
    ) -> RepoExplorerProjectionResult {
        RepoExplorerProjectionResult(
            generation: request.generation,
            snapshot: request.snapshot,
            collapsedGroupIds: request.collapsedGroupIds,
            isFiltering: request.isFiltering,
            trigger: request.trigger,
            projection: projection,
            rowIndex: RepoExplorerRowIndex(
                projection: projection,
                collapsedGroupIds: request.collapsedGroupIds,
                isFiltering: request.isFiltering
            ),
            workerDuration: .zero,
            projectionDuration: .zero,
            rowIndexDuration: .zero,
            branchStatusByWorktreeId: previous.branchStatusByWorktreeId,
            branchNameByWorktreeId: previous.branchNameByWorktreeId,
            bridgeCommandResolutionByWorktreeId: previous.bridgeCommandResolutionByWorktreeId,
            paneRowFactsByPaneId: request.paneRowFactsByPaneId,
            tabGroupFactsByTabId: request.tabGroupFactsByTabId,
            baselineRevision: nil
        )
    }
}

extension RepoExplorerProjectionResult {
    fileprivate func withBaselineRevision(_ baselineRevision: Int) -> Self {
        Self(
            generation: generation,
            snapshot: snapshot,
            collapsedGroupIds: collapsedGroupIds,
            isFiltering: isFiltering,
            trigger: trigger,
            projection: projection,
            rowIndex: rowIndex,
            workerDuration: workerDuration,
            projectionDuration: projectionDuration,
            rowIndexDuration: rowIndexDuration,
            branchStatusByWorktreeId: branchStatusByWorktreeId,
            branchNameByWorktreeId: branchNameByWorktreeId,
            bridgeCommandResolutionByWorktreeId: bridgeCommandResolutionByWorktreeId,
            paneRowFactsByPaneId: paneRowFactsByPaneId,
            tabGroupFactsByTabId: tabGroupFactsByTabId,
            baselineRevision: baselineRevision
        )
    }
}
