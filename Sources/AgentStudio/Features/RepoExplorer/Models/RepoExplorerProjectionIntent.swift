import AgentStudioCore
import Foundation

struct RepoExplorerProjectionStructuralTarget: Equatable, Sendable {
    let groupingMode: RepoExplorerGroupingMode
    let sortOrder: RepoExplorerSortOrder
    let query: String
    let collapsedGroupIDs: Set<String>
    let isFiltering: Bool

    init(request: RepoExplorerProjectionRequest) {
        groupingMode = request.snapshot.groupingMode
        sortOrder = request.snapshot.sortOrder
        query = request.snapshot.query
        collapsedGroupIDs = request.collapsedGroupIds
        isFiltering = request.isFiltering
    }
}

struct RepoExplorerProjectionDeltaIntent: Equatable, Sendable {
    let targetRequest: RepoExplorerProjectionRequest
    let changes: Set<RepoExplorerScopedProjectionChange>
    let structuralTarget: RepoExplorerProjectionStructuralTarget
}

enum RepoExplorerProjectionIntent: Equatable, Sendable {
    case full(RepoExplorerProjectionRequest)
    case delta(RepoExplorerProjectionDeltaIntent)

    var generation: Int { targetRequest.generation }

    var targetRequest: RepoExplorerProjectionRequest {
        switch self {
        case .full(let request): request
        case .delta(let delta): delta.targetRequest
        }
    }

    static func combinePending(_ pending: Self, _ latest: Self) -> Self {
        guard case .delta(let pendingDelta) = pending,
            case .delta(let latestDelta) = latest,
            pendingDelta.structuralTarget == latestDelta.structuralTarget
        else {
            return .full(latest.targetRequest)
        }
        return .delta(
            RepoExplorerProjectionDeltaIntent(
                targetRequest: latestDelta.targetRequest,
                changes: pendingDelta.changes.union(latestDelta.changes),
                structuralTarget: latestDelta.structuralTarget
            )
        )
    }
}

struct RepoExplorerProjectionWorkContext: Equatable, Sendable {
    let demandEpoch: UInt64
    let requestGeneration: Int
    let semanticBaselineSequence: UInt64
    let semanticBaselineResult: RepoExplorerProjectionResult?
    let acknowledgedBaseline: RepoExplorerMaterializationBaseline?
}

struct RepoExplorerFullProjectionWork: Equatable, Sendable {
    let targetRequest: RepoExplorerProjectionRequest
    let context: RepoExplorerProjectionWorkContext
}

struct RepoExplorerDeltaProjectionWork: Equatable, Sendable {
    let targetRequest: RepoExplorerProjectionRequest
    let changes: Set<RepoExplorerScopedProjectionChange>
    let context: RepoExplorerProjectionWorkContext
}

enum RepoExplorerProjectionWork: Equatable, Sendable {
    case full(RepoExplorerFullProjectionWork)
    case delta(RepoExplorerDeltaProjectionWork)

    var generation: Int { targetRequest.generation }

    var targetRequest: RepoExplorerProjectionRequest {
        switch self {
        case .full(let work): work.targetRequest
        case .delta(let work): work.targetRequest
        }
    }

    var context: RepoExplorerProjectionWorkContext {
        switch self {
        case .full(let work): work.context
        case .delta(let work): work.context
        }
    }
}

struct RepoExplorerProjectionCandidate: Equatable, Sendable {
    let work: RepoExplorerProjectionWork
    let result: RepoExplorerProjectionResult
    let materializationPresentation: RepoExplorerMaterializationPresentation
    let nativeUpdatePlan: RepoExplorerNativeUpdatePlan?

    init(work: RepoExplorerProjectionWork, result: RepoExplorerProjectionResult) {
        self.work = work
        self.result = result
        if let rowlessPresentation = RepoExplorerRowlessPresentation(
            emptyState: result.projection.emptyState
        ) {
            materializationPresentation = .rowless(rowlessPresentation)
        } else {
            materializationPresentation = .content(
                snapshot: result.materializationSnapshot,
                fingerprint: .make(snapshot: result.materializationSnapshot)
            )
        }
        if let acknowledgedBaseline = work.context.acknowledgedBaseline {
            switch RepoExplorerNativeUpdatePlan.validating(
                baseline: acknowledgedBaseline,
                candidate: materializationPresentation,
                requestGeneration: UInt64(work.context.requestGeneration)
            ) {
            case .success(let plan):
                nativeUpdatePlan = plan
            case .failure(let validationError):
                preconditionFailure("Invalid Repo Explorer native update plan: \(validationError)")
            }
        } else {
            nativeUpdatePlan = nil
        }
    }
}
