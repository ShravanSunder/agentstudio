import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Foundation

enum RepoExplorerScopedProjectionChange: Equatable, Sendable {
    case repo(UUID)
    case worktreeFact(UUID)
}

struct RepoExplorerProjectionRequest: Equatable, Sendable {
    let generation: Int
    let snapshot: RepoExplorerSnapshot
    let collapsedGroupIds: Set<String>
    let isFiltering: Bool
    let trigger: AppPolicies.SidebarProjection.Trigger
    let worktreeEnrichmentSnapshot: [UUID: WorktreeEnrichment]
    let pullRequestFactsSnapshot: [RepoBranchKey: PullRequestFacts]

    init(
        generation: Int,
        snapshot: RepoExplorerSnapshot,
        collapsedGroupIds: Set<String>,
        isFiltering: Bool,
        trigger: AppPolicies.SidebarProjection.Trigger,
        worktreeEnrichmentSnapshot: [UUID: WorktreeEnrichment] = [:],
        pullRequestFactsSnapshot: [RepoBranchKey: PullRequestFacts] = [:]
    ) {
        self.generation = generation
        self.snapshot = snapshot
        self.collapsedGroupIds = collapsedGroupIds
        self.isFiltering = isFiltering
        self.trigger = trigger
        self.worktreeEnrichmentSnapshot = worktreeEnrichmentSnapshot
        self.pullRequestFactsSnapshot = pullRequestFactsSnapshot
    }

    func scopedChange(from previous: Self) -> RepoExplorerScopedProjectionChange? {
        guard snapshot.groupingMode == .repo,
            previous.snapshot.groupingMode == snapshot.groupingMode,
            previous.snapshot.sortOrder == snapshot.sortOrder,
            previous.snapshot.query == snapshot.query,
            previous.snapshot.repoEnrichmentSnapshotByRepoId == snapshot.repoEnrichmentSnapshotByRepoId,
            previous.snapshot.paneLocationsByWorktreeId == snapshot.paneLocationsByWorktreeId,
            previous.snapshot.bridgePaneCommandCandidatesByWorktreeId
                == snapshot.bridgePaneCommandCandidatesByWorktreeId,
            previous.collapsedGroupIds == collapsedGroupIds,
            previous.isFiltering == isFiltering,
            previous.pullRequestFactsSnapshot == pullRequestFactsSnapshot
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
            bridgeCommandResolutionByWorktreeId: [:]
        )
    }()
}

actor RepoExplorerProjectionWorker {
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
        let projectionStart = clock.now
        let projection = try RepoExplorerProjection.projectCancellable(
            request.snapshot,
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
        let branchStatusByWorktreeId = try branchStatusByWorktreeId(
            snapshot: request.snapshot,
            worktreeEnrichmentByWorktreeId: request.worktreeEnrichmentSnapshot,
            pullRequestFactsByBranch: request.pullRequestFactsSnapshot,
            cancellationCheck: { try Task.checkCancellation() }
        )
        let branchNameByWorktreeId = try branchNameByWorktreeId(
            snapshot: request.snapshot,
            worktreeEnrichmentByWorktreeId: request.worktreeEnrichmentSnapshot,
            cancellationCheck: { try Task.checkCancellation() }
        )
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
            bridgeCommandResolutionByWorktreeId: bridgeCommandResolutionByWorktreeId
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
        cancellationCheck: () throws -> Void
    ) throws -> [UUID: GitBranchStatus] {
        let worktreeIds = snapshot.repos.flatMap(\.worktrees).map(\.id)
        var branchStatusByWorktreeId = GitBranchStatus.merge(
            worktreeEnrichmentsByWorktreeId: worktreeEnrichmentByWorktreeId,
            pullRequestFactsByBranch: pullRequestFactsByBranch
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
        let updatedGroups = previousContent.resolvedGroups.map { group in
            RepoPresentationGroup(
                id: group.id,
                repoTitle: group.repoTitle,
                organizationName: group.organizationName,
                repos: group.repos.map { replacingRepo(in: $0) }
            )
        }
        let favoriteGroups = updatedGroups.filter { !$0.repos.isEmpty && $0.repos.allSatisfy(\.isFavorite) }
        let regularGroups = updatedGroups.filter { $0.repos.contains { !$0.isFavorite } }
        let updatedLoadingRepos = previousContent.loadingRepos.map { replacingRepo(in: $0) }
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
        let enrichment = request.worktreeEnrichmentSnapshot[worktreeId]
        let pullRequestFacts =
            enrichment
            .flatMap { RepoBranchKey(repoId: $0.repoId, branch: $0.branch) }
            .flatMap { request.pullRequestFactsSnapshot[$0] }
        branchStatuses[worktreeId] = GitBranchStatus.status(
            enrichment: enrichment,
            pullRequestFacts: pullRequestFacts
        )
        branchNames[worktreeId] = branchName(enrichment: enrichment)
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
            bridgeCommandResolutionByWorktreeId: previous.bridgeCommandResolutionByWorktreeId
        )
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
            bridgeCommandResolutionByWorktreeId: previous.bridgeCommandResolutionByWorktreeId
        )
    }
}
