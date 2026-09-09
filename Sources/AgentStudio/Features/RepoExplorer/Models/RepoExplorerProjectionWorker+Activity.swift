import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

extension RepoExplorerProjectionWorker {
    static func repositoryActivityClassification(
        for request: RepoExplorerProjectionRequest
    ) -> RepositoryActivityClassification {
        RepositoryActivityClassifier.classify(
            RepositoryActivityClassificationInput(
                repositories: request.snapshot.repos.map { repository in
                    RepositoryActivityTopology(
                        repositoryID: repository.id,
                        repositoryStableKey: repository.stableKey,
                        worktreeStableKeysByID: repository.worktreeStableKeysByID
                    )
                },
                openWorktreeIDs: Set(request.snapshot.paneLocationsByWorktreeId.keys),
                localActivityHydrationDisposition: request.localActivityHydrationDisposition,
                repositoryLocalActivityByStableKey: request.repositoryLocalActivityByStableKey,
                referenceDate: request.activityReferenceDate,
                inactivityHorizon: AppPolicies.EntityRecency.applicationActivityHorizon
            )
        )
    }

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
        let preparedPresentationDeadline = RepoExplorerPreparedPresentationDeadline.prepare(
            sidebarTransitionsByPaneID: previous.sidebarPresentationTransitionAtByPaneId,
            repositoryTransitionsByRepositoryID: transitionsByRepositoryID
        )
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
            sidebarPresentationTransitionAtByPaneId: previous.sidebarPresentationTransitionAtByPaneId,
            preparedPresentationDeadline: preparedPresentationDeadline,
            semanticBaselineSequence: nil
        )
    }

    static func preparedPaneRowFacts(
        _ capturedFacts: [UUID: RepoExplorerPaneRowFacts],
        snapshot: RepoExplorerSnapshot
    ) -> [UUID: RepoExplorerPaneRowFacts] {
        guard snapshot.surface == .panes else { return capturedFacts }
        return capturedFacts.mapValues { facts in
            RepoExplorerPaneRowFacts(
                terminalTitle: facts.terminalTitle,
                activityAt: facts.activityAt,
                isPinned: facts.isPinned,
                noteText: facts.noteText,
                latestMessageText: facts.latestMessageText,
                recencyReferenceDate: facts.recencyReferenceDate,
                recencyText: RepoExplorerPaneRecencyText.display(
                    lastInteractedAt: facts.recencyReferenceDate,
                    now: snapshot.referenceDate
                ),
                recencyTier: RepoExplorerPaneRecencyTier.classify(
                    referenceDate: facts.recencyReferenceDate,
                    now: snapshot.referenceDate
                ),
                isActive: facts.isActive,
                isDrawerPane: facts.isDrawerPane
            )
        }
    }

    static func sidebarPresentationTransitions(
        _ paneFacts: [UUID: RepoExplorerPaneRowFacts],
        snapshot: RepoExplorerSnapshot
    ) -> [UUID: Date] {
        let usesActivityTime =
            snapshot.groupingMode == .activity
            || snapshot.subgroupMode == .activity
            || snapshot.sortField == .activity
        var transitions: [UUID: Date] = [:]
        transitions.reserveCapacity(paneFacts.count)
        for (paneID, facts) in paneFacts {
            let recencyTransition =
                snapshot.surface == .panes
                ? RepoExplorerPaneRecencyText.nextPresentationChangeDate(
                    referenceDate: facts.recencyReferenceDate,
                    now: snapshot.referenceDate
                )
                : nil
            let activityTransition =
                usesActivityTime
                ? RepoExplorerActivityBucket.nextChangeDate(
                    activityAt: facts.activityAt,
                    now: snapshot.referenceDate,
                    calendar: snapshot.calendar
                )
                : nil
            if let transition = [recencyTransition, activityTransition].compactMap(\.self).min() {
                transitions[paneID] = transition
            }
        }
        return transitions
    }
}
