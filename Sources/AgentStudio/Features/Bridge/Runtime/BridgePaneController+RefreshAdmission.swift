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
            retireActiveFileRefreshTask()
            retireActiveReviewRefreshTask()
        }
        return productActivityTransition
    }

    private func scheduleProductActivityTransition(
        _ activity: BridgePaneActivity
    ) -> Task<Void, Never>? {
        guard let productSchemeProvider else { return nil }
        let snapshot = refreshAdmissionCoordinator.productPresentationSnapshot
        return scheduleProductPresentationTransition {
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
        guard let productSchemeProvider else { return nil }
        let snapshot = refreshAdmissionCoordinator.productPresentationSnapshot
        return scheduleProductPresentationTransition {
            await productSchemeProvider.publishPanePresentation(snapshot, traceContext: traceContext)
        }
    }

    private func scheduleProductPresentationTransition(
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) -> Task<Void, Never> {
        productPresentationTransitionGeneration &+= 1
        let transitionGeneration = productPresentationTransitionGeneration
        let precedingTransition = productPresentationTransitionTail
        let transition = Task { @MainActor [weak self] in
            await precedingTransition?.value
            await operation()
            guard let self,
                self.productPresentationTransitionGeneration == transitionGeneration
            else { return }
            self.productPresentationTransitionTail = nil
        }
        productPresentationTransitionTail = transition
        return transition
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
            refreshAdmissionCoordinator.recordInvalidation(
                fileChangeset: matchesPaneWorktree ? changeset : nil,
                requiresReviewRefresh: true
            )
            affectsFileLane = matchesPaneWorktree
            affectsReviewLane = true
        case .statusChanged(let status):
            reserveSuccessorReviewGenerationForActiveCatchUpIfNeeded()
            refreshAdmissionCoordinator.recordInvalidation(
                fileChangeset: nil,
                latestFileStatus: status,
                requiresReviewRefresh: true
            )
            affectsFileLane = true
            affectsReviewLane = true
        }
        if affectsFileLane {
            retireActiveFileRefreshTask()
        }
        if affectsReviewLane {
            retireActiveReviewRefreshTask()
        }
        scheduleWorktreeProductCatchUpIfPossible()
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
        scheduleFileCatchUpIfPossible()
        scheduleReviewCatchUpIfPossible()
    }

    private func scheduleFileCatchUpIfPossible() {
        guard activeFileRefreshTask == nil,
            let firstReservation = refreshAdmissionCoordinator.reserveForegroundRefreshPass(for: .file)
        else { return }

        _ = scheduleProductPresentationPublication()
        let taskId = UUIDv7.generate()
        activeFileRefreshTaskId = taskId
        activeFileRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var reservation: BridgePaneRefreshCatchUpReservation? = firstReservation
            var finalOutcome = BridgePaneRefreshCatchUpOutcome.stale
            while let currentReservation = reservation, !Task.isCancelled {
                let outcome = await self.performFileCatchUp(currentReservation)
                finalOutcome = outcome
                self.refreshAdmissionCoordinator.completeRefreshPass(
                    currentReservation,
                    outcome: outcome
                )
                reservation =
                    outcome == .succeeded
                    ? self.refreshAdmissionCoordinator.reserveForegroundRefreshPass(for: .file)
                    : nil
                _ = self.scheduleProductPresentationPublication()
                guard outcome == .succeeded else { break }
            }
            self.retiringFileRefreshTaskById.removeValue(forKey: taskId)
            guard self.activeFileRefreshTaskId == taskId else { return }
            self.activeFileRefreshTask = nil
            self.activeFileRefreshTaskId = nil
            if finalOutcome != .failed {
                self.scheduleFileCatchUpIfPossible()
            }
        }
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
            while let currentReservation = reservation, !Task.isCancelled {
                let outcome = await self.performReviewCatchUp(currentReservation)
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

    func retireActiveFileRefreshTask() {
        guard let taskId = activeFileRefreshTaskId,
            let task = activeFileRefreshTask
        else { return }
        task.cancel()
        retiringFileRefreshTaskById[taskId] = task
        activeFileRefreshTask = nil
        activeFileRefreshTaskId = nil
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

    private func performFileCatchUp(
        _ reservation: BridgePaneRefreshCatchUpReservation
    ) async -> BridgePaneRefreshCatchUpOutcome {
        guard reservation.foregroundWorkAdmission.withValidAdmission({ true }) == true,
            let productAdmission = productAdmissionGate.acquire()
        else { return .stale }

        var fileRefreshFailed = false
        if let changeset = reservation.fileChangeset {
            let disposition = await productSchemeProvider?.publishFileChangeset(
                changeset,
                productAdmission: productAdmission,
                foregroundWorkAdmission: reservation.foregroundWorkAdmission
            )
            guard disposition != .stale,
                reservation.foregroundWorkAdmission.withValidAdmission({ true }) == true,
                !Task.isCancelled
            else { return .stale }
            fileRefreshFailed = fileRefreshFailed || disposition == .failed
        }

        if let status = reservation.latestFileStatus {
            let disposition = await productSchemeProvider?.publishFileStatus(
                status,
                productAdmission: productAdmission,
                foregroundWorkAdmission: reservation.foregroundWorkAdmission
            )
            guard disposition != .stale,
                reservation.foregroundWorkAdmission.withValidAdmission({ true }) == true,
                !Task.isCancelled
            else { return .stale }
            fileRefreshFailed = fileRefreshFailed || disposition == .failed
        }

        return fileRefreshFailed ? .failed : .succeeded
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
}
