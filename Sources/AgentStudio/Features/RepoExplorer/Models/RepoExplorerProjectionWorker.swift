import Foundation

struct RepoExplorerProjectionRequest: Equatable, Sendable {
    let generation: Int
    let snapshot: RepoExplorerSnapshot
    let expandedGroupIds: Set<String>
    let isFiltering: Bool
    let trigger: String
    let worktreeFactsByWorktreeId: [UUID: RepoWorktreeCacheFacts]

    init(
        generation: Int,
        snapshot: RepoExplorerSnapshot,
        expandedGroupIds: Set<String>,
        isFiltering: Bool,
        trigger: String,
        worktreeFactsByWorktreeId: [UUID: RepoWorktreeCacheFacts] = [:]
    ) {
        self.generation = generation
        self.snapshot = snapshot
        self.expandedGroupIds = expandedGroupIds
        self.isFiltering = isFiltering
        self.trigger = trigger
        self.worktreeFactsByWorktreeId = worktreeFactsByWorktreeId
    }
}

struct RepoExplorerProjectionResult: Equatable, Sendable {
    let generation: Int
    let snapshot: RepoExplorerSnapshot
    let expandedGroupIds: Set<String>
    let isFiltering: Bool
    let trigger: String
    let projection: RepoExplorerSidebarProjection
    let rowIndex: RepoExplorerRowIndex
    let workerDuration: Duration
    let projectionDuration: Duration
    let rowIndexDuration: Duration
    let branchStatusByWorktreeId: [UUID: GitBranchStatus]
    let branchNameByWorktreeId: [UUID: String]

    static let empty: Self = {
        let snapshot = RepoExplorerSnapshot(
            repos: [],
            repoEnrichmentByRepoId: [:],
            groupingMode: .repo,
            sortOrder: .default,
            query: ""
        )
        let projection = RepoExplorerSidebarProjection(
            resolvedGroups: [],
            loadingRepos: [],
            showsNoResults: false
        )
        return Self(
            generation: 0,
            snapshot: snapshot,
            expandedGroupIds: [],
            isFiltering: false,
            trigger: "startup_diagnostic",
            projection: projection,
            rowIndex: RepoExplorerRowIndex(
                projection: projection,
                expandedGroupIds: [],
                isFiltering: false
            ),
            workerDuration: .zero,
            projectionDuration: .zero,
            rowIndexDuration: .zero,
            branchStatusByWorktreeId: [:],
            branchNameByWorktreeId: [:]
        )
    }()
}

actor RepoExplorerProjectionWorker {
    func project(_ request: RepoExplorerProjectionRequest) async throws -> RepoExplorerProjectionResult {
        // Runs CPU-bound sidebar projection outside actor/main-actor isolation; cancellation is forwarded below.
        // swiftlint:disable:next no_task_detached
        let projectionTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let clock = ContinuousClock()
            let workerStart = clock.now
            let projectionStart = clock.now
            let projection = RepoExplorerProjection.project(request.snapshot)
            let projectionDuration = projectionStart.duration(to: clock.now)
            try Task.checkCancellation()
            let rowIndexStart = clock.now
            let rowIndex = RepoExplorerRowIndex(
                projection: projection,
                expandedGroupIds: request.expandedGroupIds,
                isFiltering: request.isFiltering
            )
            let rowIndexDuration = rowIndexStart.duration(to: clock.now)
            try Task.checkCancellation()
            let branchStatusByWorktreeId = Self.branchStatusByWorktreeId(
                snapshot: request.snapshot,
                worktreeFactsByWorktreeId: request.worktreeFactsByWorktreeId
            )
            let branchNameByWorktreeId = Self.branchNameByWorktreeId(
                snapshot: request.snapshot,
                worktreeFactsByWorktreeId: request.worktreeFactsByWorktreeId
            )
            try Task.checkCancellation()
            return RepoExplorerProjectionResult(
                generation: request.generation,
                snapshot: request.snapshot,
                expandedGroupIds: request.expandedGroupIds,
                isFiltering: request.isFiltering,
                trigger: request.trigger,
                projection: projection,
                rowIndex: rowIndex,
                workerDuration: workerStart.duration(to: clock.now),
                projectionDuration: projectionDuration,
                rowIndexDuration: rowIndexDuration,
                branchStatusByWorktreeId: branchStatusByWorktreeId,
                branchNameByWorktreeId: branchNameByWorktreeId
            )
        }

        return try await withTaskCancellationHandler {
            try await projectionTask.value
        } onCancel: {
            projectionTask.cancel()
        }
    }

    private static func branchStatusByWorktreeId(
        snapshot: RepoExplorerSnapshot,
        worktreeFactsByWorktreeId: [UUID: RepoWorktreeCacheFacts]
    ) -> [UUID: GitBranchStatus] {
        let worktreeIds = snapshot.repos.flatMap(\.worktrees).map(\.id)
        let worktreeEnrichmentsByWorktreeId = worktreeFactsByWorktreeId.compactMapValues(\.enrichment)
        let pullRequestCountsByWorktreeId = worktreeFactsByWorktreeId.compactMapValues(\.pullRequestCount)
        var branchStatusByWorktreeId = GitBranchStatus.merge(
            worktreeEnrichmentsByWorktreeId: worktreeEnrichmentsByWorktreeId,
            pullRequestCountsByWorktreeId: pullRequestCountsByWorktreeId
        )
        branchStatusByWorktreeId.reserveCapacity(max(branchStatusByWorktreeId.count, worktreeIds.count))
        for worktreeId in worktreeIds where branchStatusByWorktreeId[worktreeId] == nil {
            branchStatusByWorktreeId[worktreeId] = .unknown
        }
        return branchStatusByWorktreeId
    }

    private static func branchNameByWorktreeId(
        snapshot: RepoExplorerSnapshot,
        worktreeFactsByWorktreeId: [UUID: RepoWorktreeCacheFacts]
    ) -> [UUID: String] {
        Dictionary(
            uniqueKeysWithValues: snapshot.repos.flatMap(\.worktrees).map { worktree in
                (
                    worktree.id,
                    branchName(enrichment: worktreeFactsByWorktreeId[worktree.id]?.enrichment)
                )
            }
        )
    }

    private static func branchName(enrichment: WorktreeEnrichment?) -> String {
        let cachedBranch = enrichment?.branch.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cachedBranch.isEmpty {
            return cachedBranch
        }

        return "detached HEAD"
    }
}
