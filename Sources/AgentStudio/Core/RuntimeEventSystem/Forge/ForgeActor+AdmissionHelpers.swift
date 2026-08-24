import AgentStudioInfrastructure
import Foundation

extension ForgeActor {
    package func flushPerformanceSnapshot() {
        let settlementSnapshot = currentSettlementSnapshot()
        let changedSettlementSnapshot =
            settlementSnapshot == lastRecordedSettlementSnapshot ? nil : settlementSnapshot
        lastRecordedSettlementSnapshot = settlementSnapshot
        let snapshot = performanceAccumulator.takeSnapshot(settlement: changedSettlementSnapshot)
        guard !snapshot.isEmpty else { return }
        performanceTraceRecorder?.recordForgePerformanceSnapshot(snapshot)
    }

    func currentSettlementSnapshot() -> ForgePerformanceSnapshot.Settlement {
        let now = monotonicNow()
        let demandedRepositoryIds = demandedRepoIds()
        let physicallyActiveRepositoryIds = Set(providerRepoIdByRequestId.values)
        var pendingFuture = 0
        var pendingReady = 0
        var pendingCapacity = 0
        var pendingActiveFollowUp = 0
        var pendingUnclassified = 0

        for (repoId, state) in refreshStateByRepoId where state.pendingFollowUp {
            guard demandedRepositoryIds.contains(repoId), state.origin != nil else {
                pendingUnclassified += 1
                continue
            }
            if physicallyActiveRepositoryIds.contains(repoId) {
                pendingActiveFollowUp += 1
            } else if nextEligibleRefreshAt(state: state, bypassFreshness: false).map({ $0 > now }) == true {
                pendingFuture += 1
            } else if state.pendingFollowUpEligibleAt.map({ $0 > now }) == true {
                pendingCapacity += 1
            } else if providerTasksByRequestId.count >= maximumConcurrentProviderRequests {
                pendingCapacity += 1
            } else {
                pendingReady += 1
            }
        }

        let deadlines = deadlineCandidates()
        let nextDeadline = deadlines.filter { $0 > now }.min()
        let pendingTotal = pendingFuture + pendingReady + pendingCapacity + pendingActiveFollowUp + pendingUnclassified
        return ForgePerformanceSnapshot.Settlement(
            physicalActive: UInt64(clamping: providerTasksByRequestId.count),
            pendingTotal: UInt64(clamping: pendingTotal),
            pendingFuture: UInt64(clamping: pendingFuture),
            pendingReady: UInt64(clamping: pendingReady),
            pendingCapacity: UInt64(clamping: pendingCapacity),
            pendingActiveFollowUp: UInt64(clamping: pendingActiveFollowUp),
            pendingUnclassified: UInt64(clamping: pendingUnclassified),
            deadlineOverdue: UInt64(clamping: deadlines.count { $0 <= now }),
            deadlineNextMilliseconds: nextDeadline.map {
                AgentStudioPerformanceTraceRecorder.milliseconds(from: max(.zero, $0 - now))
            } ?? 0
        )
    }

    func deadlineCandidates() -> [Duration] {
        demandedRepoIds().compactMap { repoId -> Duration? in
            guard let state = refreshStateByRepoId[repoId],
                state.origin != nil,
                state.activeRequestId == nil
            else { return nil }
            return state.pendingFollowUpEligibleAt
                ?? nextEligibleRefreshAt(state: state, bypassFreshness: false)
        }
    }

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
        recordPhysicalPerformanceState()
        return true
    }

    func recordPhysicalPerformanceState() {
        performanceAccumulator.recordPhysicalState(
            active: providerTasksByRequestId.count,
            pending: refreshStateByRepoId.values.filter(\.pendingFollowUp).count
        )
    }

    func recordQueryPlan(for request: ProviderRequest) {
        let batchCapacity = AppPolicies.ForgeRefresh.maximumBranchAliasesPerBatch
        performanceAccumulator.recordQueryPlan(
            demandedBranchCount: request.demandedBranches.count,
            aliasBatchCount: max(1, (request.demandedBranches.count + batchCapacity - 1) / batchCapacity)
        )
    }
}
