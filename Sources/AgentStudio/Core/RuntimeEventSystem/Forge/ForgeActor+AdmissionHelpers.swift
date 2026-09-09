import AgentStudioInfrastructure
import Foundation

extension ForgeActor {
    var providerCapacityOccupancyCount: Int {
        var capacityOccupyingRequestIds = Set(providerTasksByRequestId.keys)
        capacityOccupyingRequestIds.formUnion(
            refreshStateByRepoId.values.compactMap(\.activeRequestId)
        )
        return capacityOccupyingRequestIds.count
    }

    var providerCapacityOccupyingRepoIds: Set<UUID> {
        var capacityOccupyingRepoIds = Set(providerRepoIdByRequestId.values)
        for (repoId, state) in refreshStateByRepoId where state.activeRequestId != nil {
            capacityOccupyingRepoIds.insert(repoId)
        }
        return capacityOccupyingRepoIds
    }

    func coalesceRefreshWhileProviderActive(
        repoId: UUID,
        trigger: RefreshTrigger,
        state: inout RepositoryRefreshState
    ) -> Bool {
        guard state.activeRequestId != nil else { return false }
        performanceAccumulator.recordAdmission(.activeRequestCoalesced)
        state.pendingFollowUp = true
        state.pendingFollowUpRequiresRefresh =
            state.pendingFollowUpRequiresRefresh || trigger.requiresFollowUpRefresh
        state.pendingFollowUpHasUnconfirmedScopeChange =
            state.pendingFollowUpHasUnconfirmedScopeChange || trigger.hasUnconfirmedScopeChange
        refreshStateByRepoId[repoId] = state
        return true
    }

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
        let demandedRepositoryIds = repositoryFactRefreshRepoIds()
        let capacityOccupyingRepositoryIds = providerCapacityOccupyingRepoIds
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
            if capacityOccupyingRepositoryIds.contains(repoId) {
                pendingActiveFollowUp += 1
            } else if nextEligibleRefreshAt(
                state: state,
                bypassFreshness: pendingFollowUpTrigger(for: state).bypassesFreshness
            ).map({ $0 > now }) == true {
                pendingFuture += 1
            } else if state.pendingFollowUpEligibleAt.map({ $0 > now }) == true {
                pendingCapacity += 1
            } else if providerCapacityOccupancyCount >= maximumConcurrentProviderRequests {
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
        repositoryFactRefreshRepoIds().compactMap(deadlineCandidate(repoId:))
    }

    func deadlineCandidate(repoId: UUID) -> Duration? {
        guard let state = refreshStateByRepoId[repoId],
            state.origin != nil,
            state.activeRequestId == nil,
            !repositoryFactRefreshBranches(repoId: repoId).isEmpty
        else { return nil }
        if state.pendingFollowUp {
            return state.pendingFollowUpEligibleAt
        }
        return nextEligibleRefreshAt(state: state, bypassFreshness: false)
    }

    func consumeCapacityFallbacksDue(at now: Duration) -> Bool {
        guard providerCapacityOccupancyCount >= maximumConcurrentProviderRequests else {
            return false
        }

        var consumedFallback = false
        for repoId in repositoryFactRefreshRepoIds() {
            guard let deadline = deadlineCandidate(repoId: repoId),
                deadline <= now,
                var state = refreshStateByRepoId[repoId]
            else { continue }
            state.pendingFollowUp = true
            state.pendingFollowUpEligibleAt = nil
            refreshStateByRepoId[repoId] = state
            performanceAccumulator.recordAdmission(.capacityLimited)
            consumedFallback = true
        }
        if consumedFallback {
            recordPhysicalPerformanceState()
        }
        return consumedFallback
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
        } else if providerCapacityOccupancyCount >= maximumConcurrentProviderRequests {
            admissionOutcome = .capacityLimited
        } else {
            return false
        }

        performanceAccumulator.recordAdmission(admissionOutcome)
        state.pendingFollowUp = true
        state.pendingFollowUpRequiresRefresh =
            state.pendingFollowUpRequiresRefresh || trigger.requiresFollowUpRefresh
        state.pendingFollowUpHasUnconfirmedScopeChange =
            state.pendingFollowUpHasUnconfirmedScopeChange || trigger.hasUnconfirmedScopeChange
        state.pendingFollowUpEligibleAt = max(
            state.pendingFollowUpEligibleAt
                ?? now + AppPolicies.ForgeRefresh.capacityRecheckDelay,
            now + AppPolicies.ForgeRefresh.capacityRecheckDelay
        )
        refreshStateByRepoId[repoId] = state
        recordPhysicalPerformanceState()
        return true
    }

    func pendingFollowUpTrigger(for state: RepositoryRefreshState) -> RefreshTrigger {
        if state.pendingFollowUpRequiresRefresh { return .manualFollowUp }
        if state.pendingFollowUpHasUnconfirmedScopeChange { return .scopeChanged }
        return .followUp
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
