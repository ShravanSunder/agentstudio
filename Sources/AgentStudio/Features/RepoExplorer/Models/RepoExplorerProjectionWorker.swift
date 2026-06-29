import Foundation

struct RepoExplorerProjectionRequest: Equatable, Sendable {
    let generation: Int
    let snapshot: RepoExplorerSnapshot
    let expandedGroupIds: Set<String>
    let isFiltering: Bool
    let trigger: String
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
            rowIndexDuration: .zero
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
                rowIndexDuration: rowIndexDuration
            )
        }

        return try await withTaskCancellationHandler {
            try await projectionTask.value
        } onCancel: {
            projectionTask.cancel()
        }
    }
}
