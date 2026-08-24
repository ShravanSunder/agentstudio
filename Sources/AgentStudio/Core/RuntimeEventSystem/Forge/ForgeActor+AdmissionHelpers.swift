import AgentStudioInfrastructure
import Foundation

extension ForgeActor {
    func deferStartIfPhysicallyBlocked(
        repoId: UUID,
        trigger: RefreshTrigger,
        now: Duration,
        state: inout RepositoryRefreshState
    ) -> Bool {
        let admissionOutcome: ForgePerformanceAdmissionOutcome
        if providerRepoIdByRequestId.values.contains(repoId) {
            admissionOutcome = .activeRequestCoalesced
        } else if providerTasksByRequestId.count >= maximumConcurrentProviderRequests {
            admissionOutcome = .capacityLimited
        } else {
            return false
        }

        performanceAccumulator.recordAdmission(admissionOutcome)
        state.pendingFollowUp = true
        state.pendingFollowUpRequiresRefresh =
            state.pendingFollowUpRequiresRefresh || trigger.requiresFollowUpRefresh
        state.pendingFollowUpEligibleAt = min(
            state.pendingFollowUpEligibleAt
                ?? now + AppPolicies.ForgeRefresh.capacityRecheckDelay,
            now + AppPolicies.ForgeRefresh.capacityRecheckDelay
        )
        refreshStateByRepoId[repoId] = state
        return true
    }
}
