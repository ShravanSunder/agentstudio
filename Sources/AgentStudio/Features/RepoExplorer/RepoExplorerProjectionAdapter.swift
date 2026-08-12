import AgentStudioInfrastructure
import Observation

private enum RepoExplorerProjectionSlot: Hashable, Sendable {
    case sidebar
}

typealias RepoExplorerMaterializedProjection = EagerDerivedAtom<
    RepoExplorerProjectionRequest,
    Int,
    RepoExplorerProjectionResult
>

private typealias RepoExplorerMaterializedProjectionFamily = EagerDerivedAtomFamily<
    RepoExplorerProjectionSlot,
    RepoExplorerProjectionRequest,
    Int,
    RepoExplorerProjectionResult
>

@MainActor
@Observable
final class RepoExplorerProjectionAdapter {
    private(set) var publishedResult: RepoExplorerProjectionResult?
    @ObservationIgnored private var projectionFamily: RepoExplorerMaterializedProjectionFamily!
    @ObservationIgnored private var hasStopped = false

    init(
        project:
            @escaping @Sendable (RepoExplorerProjectionRequest) throws(CancellationError)
            -> RepoExplorerProjectionResult = { request throws(CancellationError) in
                do {
                    return try RepoExplorerProjectionWorker.project(request)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    preconditionFailure("Repo Explorer projection threw a non-cancellation error: \(error)")
                }
            }
    ) {
        projectionFamily = RepoExplorerMaterializedProjectionFamily(
            requestIdentity: \.generation,
            isValueEqual: Self.hasEqualPublishedContent,
            project: project,
            onProjectionCompletion: { [weak self] _, completion in
                self?.handleProjectionCompletion(completion)
            }
        )
        _ = projectionFamily.materialize(for: .sidebar)
    }

    var materializedProjection: RepoExplorerMaterializedProjection? {
        projectionFamily.atom(for: .sidebar)
    }

    func admit(_ request: RepoExplorerProjectionRequest) {
        guard !hasStopped else { return }
        projectionFamily.admit(request, for: .sidebar)
    }

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true
        projectionFamily.stop()
    }

    private func handleProjectionCompletion(
        _ completion: RepoExplorerMaterializedProjection.ProjectionCompletion
    ) {
        guard case .published = completion,
            let result = projectionFamily.currentValue(for: .sidebar)
        else { return }
        publishedResult = result
    }

    private nonisolated static func hasEqualPublishedContent(
        _ lhs: RepoExplorerProjectionResult,
        _ rhs: RepoExplorerProjectionResult
    ) -> Bool {
        lhs.snapshot == rhs.snapshot
            && lhs.collapsedGroupIds == rhs.collapsedGroupIds
            && lhs.isFiltering == rhs.isFiltering
            && lhs.projection == rhs.projection
            && lhs.rowIndex == rhs.rowIndex
            && lhs.branchStatusByWorktreeId == rhs.branchStatusByWorktreeId
            && lhs.branchNameByWorktreeId == rhs.branchNameByWorktreeId
    }
}
