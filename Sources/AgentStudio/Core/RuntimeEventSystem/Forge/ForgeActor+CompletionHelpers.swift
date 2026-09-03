import AgentStudioInfrastructure
import Foundation

extension ForgeActor {
    func validatedStateForProviderCompletion(
        _ request: ProviderRequest
    ) async -> RepositoryRefreshState? {
        guard let state = refreshStateByRepoId[request.repoId] else {
            await rejectObsoleteProviderCompletion(request, validation: .staleGeneration)
            return nil
        }
        guard state.generation == request.generation else {
            await rejectObsoleteProviderCompletion(request, validation: .staleGeneration)
            return nil
        }
        guard state.origin == request.origin else {
            await rejectObsoleteProviderCompletion(request, validation: .staleOrigin)
            return nil
        }
        guard state.activeRequestId == request.id else {
            performanceAccumulator.recordExecution(.superseded)
            settleExplicitUpdateAttempts(matching: request, outcome: .obsolete, requiresMatchingScope: false)
            await rearmAfterProviderPhysicalCompletion()
            return nil
        }
        return state
    }

    private func rejectObsoleteProviderCompletion(
        _ request: ProviderRequest,
        validation: ForgePerformanceValidationOutcome
    ) async {
        performanceAccumulator.recordExecution(.superseded)
        performanceAccumulator.recordValidation(validation)
        settleExplicitUpdateAttempts(matching: request, outcome: .obsolete, requiresMatchingScope: false)
        await rearmAfterProviderPhysicalCompletion()
    }

    func settleExplicitUpdateAttempts(
        matching request: ProviderRequest,
        outcome: RepositoryFactSourceUpdateOutcome,
        requiresMatchingScope: Bool
    ) {
        let matchingCurrentAttemptIds: [UUID] = explicitUpdateAttemptsById.compactMap { attemptId, attempt in
            guard attempt.repoId == request.repoId,
                attempt.generation == request.generation,
                attempt.origin == request.origin,
                !requiresMatchingScope || attempt.branches == request.demandedBranches
            else { return nil }
            return attemptId
        }
        let candidateAttemptIds = request.explicitAttemptIds.union(matchingCurrentAttemptIds)
        var settledCount = 0
        for attemptId in candidateAttemptIds {
            guard let attempt = explicitUpdateAttemptsById[attemptId] else { continue }
            if requiresMatchingScope,
                attempt.generation == request.generation,
                attempt.origin == request.origin,
                attempt.branches != request.demandedBranches
            {
                continue
            }
            explicitUpdateAttemptsById.removeValue(forKey: attemptId)
            attempt.settlement.resolve(outcome)
            settledCount += 1
        }
        performanceAccumulator.recordExplicitSettlement(outcome, count: settledCount)
        flushPerformanceSnapshot()
    }

    func settleAllExplicitUpdateAttempts(_ outcome: RepositoryFactSourceUpdateOutcome) {
        let attempts = explicitUpdateAttemptsById.values
        let settledCount = attempts.count
        explicitUpdateAttemptsById.removeAll(keepingCapacity: false)
        for attempt in attempts {
            attempt.settlement.resolve(outcome)
        }
        performanceAccumulator.recordExplicitSettlement(outcome, count: settledCount)
        flushPerformanceSnapshot()
    }

    func settleExplicitUpdateAttemptsAfterLogicalInvalidation(repoId: UUID) {
        guard !providerRepoIdByRequestId.values.contains(repoId) else { return }
        var settledCount = 0
        for attemptId in explicitUpdateAttemptsById.keys {
            guard let attempt = explicitUpdateAttemptsById[attemptId], attempt.repoId == repoId else { continue }
            explicitUpdateAttemptsById.removeValue(forKey: attemptId)
            attempt.settlement.resolve(.obsolete)
            settledCount += 1
        }
        performanceAccumulator.recordExplicitSettlement(.obsolete, count: settledCount)
        flushPerformanceSnapshot()
    }

    func captureFollowUpDecision(
        state: inout RepositoryRefreshState,
        request: ProviderRequest,
        completionTime: Duration
    ) -> RefreshTrigger? {
        guard state.pendingFollowUp else { return nil }
        let currentSignature = state.origin.map {
            ProviderRequestSignature(
                origin: $0,
                demandedBranches: repositoryFactRefreshBranches(repoId: request.repoId)
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
        let deferredRepoIds = repositoryFactRefreshRepoIds().sorted { lhs, rhs in
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

        return repositoryFactRefreshBranches(repoId: request.repoId) == request.demandedBranches
            && request.demandedBranches.isSubset(
                of: representedBranches(repoId: request.repoId)
            )
    }
}
