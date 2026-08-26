import AgentStudioInfrastructure
import Foundation

extension ForgeActor {
    func captureFollowUpDecision(
        state: inout RepositoryRefreshState,
        request: ProviderRequest,
        completionTime: Duration
    ) -> RefreshTrigger? {
        guard state.pendingFollowUp else { return nil }
        let currentSignature = state.origin.map {
            ProviderRequestSignature(
                origin: $0,
                demandedBranches: demandedBranches(repoId: request.repoId)
            )
        }
        if state.pendingFollowUpRequiresRefresh {
            state.pendingFollowUp = false
            state.pendingFollowUpRequiresRefresh = false
            state.pendingFollowUpHasUnconfirmedScopeChange = false
            state.pendingFollowUpEligibleAt = nil
            return .manualFollowUp
        }
        if currentSignature != request.signature {
            state.pendingFollowUp = false
            state.pendingFollowUpRequiresRefresh = false
            state.pendingFollowUpHasUnconfirmedScopeChange = false
            state.pendingFollowUpEligibleAt = nil
            return .scopeChanged
        }

        state.pendingFollowUpRequiresRefresh = false
        state.pendingFollowUpHasUnconfirmedScopeChange = false
        state.pendingFollowUpEligibleAt =
            completionTime + AppPolicies.ForgeRefresh.pendingFollowUpDelay
        performanceAccumulator.recordAdmission(.freshnessDeferred)
        return nil
    }

    func rearmAfterProviderPhysicalCompletion() async {
        guard !isShuttingDown else { return }
        let deferredRepoIds = demandedRepoIds().sorted { lhs, rhs in
            lhs.uuidString < rhs.uuidString
        }
        for repoId in deferredRepoIds {
            guard providerCapacityOccupancyCount < maximumConcurrentProviderRequests,
                let state = refreshStateByRepoId[repoId],
                state.activeRequestId == nil,
                state.pendingFollowUp
            else { continue }
            let trigger = pendingFollowUpTrigger(for: state)
            await requestRefreshIfDemanded(
                repoId: repoId,
                trigger: trigger,
                correlationId: nil
            )
        }
        rescheduleDeadline()
    }

    func applyFailureHonestyThreshold(to state: inout RepositoryRefreshState) {
        guard !state.hasEmittedUnavailable,
            state.consecutiveUnsuccessfulAttempts
                >= AppPolicies.Forge.consecutiveFailureHonestyThreshold
        else { return }
        performanceAccumulator.recordUnavailableTransition()
        state.hasEmittedUnavailable = true
        state.stablePresentation = .unavailable(
            previousConfirmedFactsByBranch: ForgePresentationFacts.confirmedFacts(
                in: state.stablePresentation
            )
        )
    }

    func requestRemainsCurrentForResultPublication(_ request: ProviderRequest) -> Bool {
        guard !isShuttingDown,
            let currentState = refreshStateByRepoId[request.repoId],
            currentState.generation == request.generation,
            currentState.origin == request.origin
        else { return false }

        return demandedBranches(repoId: request.repoId) == request.demandedBranches
            && request.demandedBranches.isSubset(
                of: representedBranches(repoId: request.repoId)
            )
    }
}
