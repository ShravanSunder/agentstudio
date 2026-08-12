import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Foundation

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
            let branchStatusByWorktreeId = try Self.branchStatusByWorktreeId(
                snapshot: request.snapshot,
                worktreeEnrichmentByWorktreeId: request.worktreeEnrichmentSnapshot,
                pullRequestFactsByBranch: request.pullRequestFactsSnapshot,
                cancellationCheck: { try Task.checkCancellation() }
            )
            let branchNameByWorktreeId = try Self.branchNameByWorktreeId(
                snapshot: request.snapshot,
                worktreeEnrichmentByWorktreeId: request.worktreeEnrichmentSnapshot,
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
}
