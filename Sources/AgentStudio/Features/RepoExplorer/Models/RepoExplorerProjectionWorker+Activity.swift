import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

extension RepoExplorerProjectionWorker {
    static func applyScopedRepositoryActivityChanges(
        _ repositoryIDs: [UUID],
        request: RepoExplorerProjectionRequest,
        previous: RepoExplorerProjectionResult
    ) throws -> RepoExplorerProjectionResult? {
        var result = previous
        for repositoryID in repositoryIDs {
            try Task.checkCancellation()
            guard
                let updated = applyScopedRepositoryActivityChange(
                    repositoryID: repositoryID,
                    request: request,
                    previous: result
                )
            else { return nil }
            result = updated
        }
        return result
    }

    static func applyScopedRepositoryActivityChange(
        repositoryID: UUID,
        request: RepoExplorerProjectionRequest,
        previous: RepoExplorerProjectionResult
    ) -> RepoExplorerProjectionResult? {
        guard let repository = request.snapshot.repos.first(where: { $0.id == repositoryID }) else {
            return nil
        }
        let activityByRepositoryStableKey =
            request.repositoryLocalActivityByStableKey[
                repository.stableKey
            ].map { [repository.stableKey: $0] } ?? [:]
        let classification = RepositoryActivityClassifier.classify(
            RepositoryActivityClassificationInput(
                repositories: [
                    RepositoryActivityTopology(
                        repositoryID: repository.id,
                        repositoryStableKey: repository.stableKey,
                        worktreeStableKeysByID: repository.worktreeStableKeysByID
                    )
                ],
                openWorktreeIDs: Set(request.snapshot.paneLocationsByWorktreeId.keys),
                localActivityHydrationDisposition: request.localActivityHydrationDisposition,
                repositoryLocalActivityByStableKey: activityByRepositoryStableKey,
                referenceDate: request.activityReferenceDate,
                inactivityHorizon: AppPolicies.EntityRecency.applicationActivityHorizon
            )
        )
        guard let disposition = classification.dispositionByRepositoryID[repositoryID] else {
            return nil
        }

        var dispositionsByRepositoryID = previous.repositoryActivityDispositionByRepoId
        dispositionsByRepositoryID[repositoryID] = disposition
        var transitionsByRepositoryID = previous.repositoryActivityTransitionAtByRepoId
        transitionsByRepositoryID[repositoryID] = classification.transitionAtByRepositoryID[repositoryID]
        let materializationSnapshot = previous.materializationSnapshot
            .replacingRepositoryActivityDisposition(
                repositoryID: repositoryID,
                disposition: disposition
            )
        return RepoExplorerProjectionResult(
            generation: request.generation,
            snapshot: request.snapshot,
            collapsedGroupIds: request.collapsedGroupIds,
            isFiltering: request.isFiltering,
            trigger: request.trigger,
            projection: previous.projection,
            rowIndex: previous.rowIndex,
            materializationSnapshot: materializationSnapshot,
            workerDuration: .zero,
            projectionDuration: .zero,
            rowIndexDuration: .zero,
            branchStatusByWorktreeId: previous.branchStatusByWorktreeId,
            branchNameByWorktreeId: previous.branchNameByWorktreeId,
            bridgeCommandResolutionByWorktreeId: previous.bridgeCommandResolutionByWorktreeId,
            paneRowFactsByPaneId: request.paneRowFactsByPaneId,
            tabGroupFactsByTabId: request.tabGroupFactsByTabId,
            repositoryActivityDispositionByRepoId: dispositionsByRepositoryID,
            repositoryActivityTransitionAtByRepoId: transitionsByRepositoryID,
            semanticBaselineSequence: nil
        )
    }
}
