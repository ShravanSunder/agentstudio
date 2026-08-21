import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

package enum BridgePaneWorktreeProductInvalidation: Sendable {
    case filesChanged(FileChangeset)
    case statusChanged(GitWorkingTreeStatus)

    package var isGitInternalFileInvalidation: Bool {
        switch self {
        case .filesChanged(let changeset):
            changeset.containsGitInternalChanges
                || changeset.suppressedGitInternalPathCount > 0
        case .statusChanged:
            false
        }
    }
}

@MainActor
extension BridgePaneController {
    func admitPreparedReviewPackageRefresh(
        currentPublication: BridgeReviewCommittedPublication,
        refreshGeneration: BridgeReviewGeneration,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        productAdmission: BridgeProductAdmissionContext,
        reservation: BridgePaneRefreshCatchUpReservation,
        packageTraceContext: BridgeTraceContext?
    ) -> Bool {
        !Task.isCancelled
            && foregroundWorkAdmission.withValidAdmission({ true }) == true
            && refreshAdmissionCoordinator.isRefreshPassCurrent(reservation)
            && refreshGeneration == nextReviewGeneration
            && reviewPublicationCoordinator.committedPublicationForReplay(
                productAdmission: productAdmission
            )?.publicationId == currentPublication.publicationId
            && productAdmission.withValidAdmission({
                lastReviewPackageTraceContext = packageTraceContext
                return true
            }) == true
    }

    @discardableResult
    package func applyBridgePaneActivity(_ activity: BridgePaneActivity) -> Task<Void, Never>? {
        let previousActivity = refreshAdmissionCoordinator.diagnosticSnapshot.activity
        refreshAdmissionCoordinator.applyActivity(activity)
        let productActivityTransition =
            previousActivity == activity ? nil : scheduleProductActivityTransition(activity)
        if activity == .foreground {
            scheduleInitialReviewPackageLoadIfPossible()
            scheduleWorktreeProductCatchUpIfPossible()
        } else {
            if activeReviewRefreshTask != nil {
                refreshAdmissionCoordinator.recordInvalidation(
                    fileChangeset: nil,
                    requiresReviewRefresh: true
                )
            }
            worktreeRefreshDriver.retireActiveFileOperation()
            retireActiveReviewRefreshTask()
        }
        return productActivityTransition
    }

    package func retryUnavailableFileRefresh() {
        worktreeRefreshDriver.retryUnavailableFileRefresh()
    }

    private func scheduleProductActivityTransition(
        _ activity: BridgePaneActivity
    ) -> Task<Void, Never>? {
        guard let productSchemeProvider else { return nil }
        return worktreeRefreshDriver.schedulePresentationTransition { snapshot in
            if activity == .foreground {
                await productSchemeProvider.resumeForegroundWork()
                await productSchemeProvider.publishPanePresentation(snapshot)
            } else {
                await productSchemeProvider.publishPanePresentation(snapshot)
                await productSchemeProvider.suspendForegroundWork()
            }
        }
    }

    func scheduleProductPresentationPublication(
        traceContext: BridgeTraceContext? = nil
    ) -> Task<Void, Never>? {
        worktreeRefreshDriver.schedulePresentationPublication(traceContext: traceContext)
    }

    package func handleWorktreeProductInvalidation(
        _ invalidation: BridgePaneWorktreeProductInvalidation
    ) async {
        let affectsFileLane: Bool
        let affectsReviewLane: Bool
        switch invalidation {
        case .filesChanged(let changeset):
            let matchesPaneWorktree = changeset.worktreeId == runtime.metadata.worktreeId
            let admitsCrossWorktreeContributionRefresh: Bool
            if case .workspace(_, let baseline) = bridgePaneState.source {
                admitsCrossWorktreeContributionRefresh =
                    invalidation.isGitInternalFileInvalidation
                    && baseline?.contributionTarget != nil
            } else {
                admitsCrossWorktreeContributionRefresh = false
            }
            guard changeset.repoId == runtime.metadata.repoId,
                matchesPaneWorktree || admitsCrossWorktreeContributionRefresh
            else { return }
            reserveSuccessorReviewGenerationForActiveCatchUpIfNeeded()
            let affectedLanes = worktreeRefreshDriver.recordInvalidation(
                fileChangeset: matchesPaneWorktree ? changeset : nil,
                requiresReviewRefresh: true
            )
            affectsFileLane = affectedLanes.contains(.file)
            affectsReviewLane = affectedLanes.contains(.review)
        case .statusChanged(let status):
            reserveSuccessorReviewGenerationForActiveCatchUpIfNeeded()
            let affectedLanes = worktreeRefreshDriver.recordInvalidation(
                fileChangeset: nil,
                latestFileStatus: status,
                requiresReviewRefresh: true
            )
            affectsFileLane = affectedLanes.contains(.file)
            affectsReviewLane = affectedLanes.contains(.review)
        }
        if affectsReviewLane {
            retireActiveReviewRefreshTask()
        }
        if affectsFileLane || affectsReviewLane {
            scheduleWorktreeProductCatchUpIfPossible()
        }
    }

    private func reserveSuccessorReviewGenerationForActiveCatchUpIfNeeded() {
        let admissionSnapshot = refreshAdmissionCoordinator.diagnosticSnapshot
        guard admissionSnapshot.activity == .foreground,
            refreshAdmissionCoordinator.isRefreshLaneActive(.review),
            pendingComparisonReviewGeneration == nil,
            case .workspace(_, let baseline) = bridgePaneState.source,
            baseline?.contributionTarget != nil
        else { return }

        let successorGeneration = nextReviewGeneration.next()
        nextReviewGeneration = successorGeneration
        pendingComparisonReviewGeneration = successorGeneration
    }

    func scheduleWorktreeProductCatchUpIfPossible() {
        worktreeRefreshDriver.scheduleFileCatchUpIfPossible()
        scheduleReviewCatchUpIfPossible()
    }

    private func scheduleReviewCatchUpIfPossible() {
        guard activeReviewRefreshTask == nil,
            let firstReservation = refreshAdmissionCoordinator.reserveForegroundRefreshPass(for: .review)
        else { return }

        _ = scheduleProductPresentationPublication()
        let taskId = UUIDv7.generate()
        activeReviewRefreshTaskId = taskId
        activeReviewRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var reservation: BridgePaneRefreshCatchUpReservation? = firstReservation
            var finalOutcome = BridgePaneRefreshCatchUpOutcome.stale
            while let currentReservation = reservation {
                await self.productSchemeProvider?.recordOperationLifecycle(
                    operationCorrelationID: currentReservation.operationCorrelationID,
                    result: .success,
                    stage: .refreshReserved,
                    stageAttempt: currentReservation.operationStageAttempt,
                    surface: .review
                )
                await self.productSchemeProvider?.recordOperationLifecycle(
                    operationCorrelationID: currentReservation.operationCorrelationID,
                    result: .started,
                    stage: .reviewPrepareStarted,
                    stageAttempt: currentReservation.operationStageAttempt,
                    surface: .review
                )
                let outcome = await self.performReviewCatchUp(currentReservation)
                await self.productSchemeProvider?.recordOperationLifecycle(
                    operationCorrelationID: currentReservation.operationCorrelationID,
                    result: Self.operationResult(for: outcome),
                    stage: .reviewPrepareTerminal,
                    stageAttempt: currentReservation.operationStageAttempt,
                    surface: .review
                )
                await self.productSchemeProvider?.recordOperationLifecycle(
                    operationCorrelationID: currentReservation.operationCorrelationID,
                    result: Self.operationResult(for: outcome),
                    stage: .refreshOperationTerminal,
                    stageAttempt: currentReservation.operationStageAttempt,
                    surface: .review
                )
                finalOutcome = outcome
                self.refreshAdmissionCoordinator.completeRefreshPass(
                    currentReservation,
                    outcome: outcome
                )
                reservation =
                    outcome == .succeeded
                    ? self.refreshAdmissionCoordinator.reserveForegroundRefreshPass(for: .review)
                    : nil
                _ = self.scheduleProductPresentationPublication()
                guard outcome == .succeeded else { break }
            }
            self.retiringReviewRefreshTaskById.removeValue(forKey: taskId)
            guard self.activeReviewRefreshTaskId == taskId else { return }
            self.activeReviewRefreshTask = nil
            self.activeReviewRefreshTaskId = nil
            self.scheduleRetainedReviewPackageBuildIfPossible()
            if finalOutcome != .failed {
                self.scheduleReviewCatchUpIfPossible()
            }
        }
    }

    func retireActiveReviewRefreshTask() {
        if let productAdmission = productAdmissionGate.acquire() {
            reviewPublicationCoordinator.supersedePendingPublication(
                productAdmission: productAdmission
            )
        }
        guard let taskId = activeReviewRefreshTaskId,
            let task = activeReviewRefreshTask
        else { return }
        task.cancel()
        retiringReviewRefreshTaskById[taskId] = task
        activeReviewRefreshTask = nil
        activeReviewRefreshTaskId = nil
    }

    private func performReviewCatchUp(
        _ reservation: BridgePaneRefreshCatchUpReservation
    ) async -> BridgePaneRefreshCatchUpOutcome {
        guard reservation.foregroundWorkAdmission.withValidAdmission({ true }) == true,
            let productAdmission = productAdmissionGate.acquire()
        else { return .stale }
        return await refreshCurrentReviewPackage(
            reservation: reservation,
            foregroundWorkAdmission: reservation.foregroundWorkAdmission,
            productAdmission: productAdmission
        )
    }

    private static func operationResult(
        for outcome: BridgePaneRefreshCatchUpOutcome
    ) -> BridgeOperationLifecycleTraceEvent.Result {
        switch outcome {
        case .succeeded:
            .success
        case .failed:
            .failure
        case .stale, .streamReset:
            .stale
        }
    }
}
