import AgentStudioCore
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
            activeReviewRefreshTask?.cancel()
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
            refreshAdmissionCoordinator.recordInvalidation(
                fileChangeset: matchesPaneWorktree ? changeset : nil,
                requiresReviewRefresh: true
            )
        case .statusChanged(let status):
            refreshAdmissionCoordinator.recordInvalidation(
                fileChangeset: nil,
                latestFileStatus: status,
                requiresReviewRefresh: true
            )
        }
        reserveSuccessorReviewGenerationForActiveCatchUpIfNeeded()
        scheduleWorktreeProductCatchUpIfPossible()
    }

    private func reserveSuccessorReviewGenerationForActiveCatchUpIfNeeded() {
        let admissionSnapshot = refreshAdmissionCoordinator.diagnosticSnapshot
        guard admissionSnapshot.activity == .foreground,
            admissionSnapshot.activeRefreshPass?.lanes.contains(.review) == true,
            pendingComparisonReviewGeneration == nil,
            case .workspace(_, let baseline) = bridgePaneState.source,
            baseline?.contributionTarget != nil
        else { return }

        let successorGeneration = nextReviewGeneration.next()
        nextReviewGeneration = successorGeneration
        pendingComparisonReviewGeneration = successorGeneration
    }

    func scheduleWorktreeProductCatchUpIfPossible() {
        guard activeReviewRefreshTask == nil,
            let firstReservation = refreshAdmissionCoordinator.reserveForegroundRefreshPass()
        else { return }

        _ = scheduleProductPresentationPublication()
        activeReviewRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var reservation: BridgePaneRefreshCatchUpReservation? = firstReservation
            var finalOutcome = BridgePaneRefreshCatchUpOutcome.stale
            while let currentReservation = reservation, !Task.isCancelled {
                let outcome = await self.performWorktreeProductCatchUp(currentReservation)
                finalOutcome = outcome
                self.refreshAdmissionCoordinator.completeRefreshPass(
                    currentReservation,
                    outcome: outcome
                )
                reservation =
                    outcome == .succeeded
                    ? self.refreshAdmissionCoordinator.reserveForegroundRefreshPass()
                    : nil
                _ = self.scheduleProductPresentationPublication()
                guard outcome == .succeeded else { break }
            }
            self.activeReviewRefreshTask = nil
            self.scheduleRetainedReviewPackageBuildIfPossible()
            if finalOutcome != .failed {
                self.scheduleWorktreeProductCatchUpIfPossible()
            }
        }
    }

    private func performWorktreeProductCatchUp(
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

        guard reservation.requiresReviewRefresh else {
            return fileRefreshFailed ? .failed : .succeeded
        }
        let reviewOutcome = await refreshCurrentReviewPackage(
            foregroundWorkAdmission: reservation.foregroundWorkAdmission,
            productAdmission: productAdmission
        )
        guard reviewOutcome == .succeeded else { return reviewOutcome }
        return fileRefreshFailed ? .failed : .succeeded
    }
}
