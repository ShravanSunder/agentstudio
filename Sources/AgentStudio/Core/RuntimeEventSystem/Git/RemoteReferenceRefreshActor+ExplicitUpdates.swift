import Foundation

extension RemoteReferenceRefreshActor {
    package func refresh(repoId: UUID) {
        guard !isShuttingDown, demandedRepositoryIds.contains(repoId), registrationsByRepoId[repoId] != nil else {
            return
        }
        explicitRepositoryIds.insert(repoId)
        pendingRepositoryIds.insert(repoId)
        admitPendingAttempts()
        rescheduleDeadline()
    }

    package func waitUntilIdle() async {
        guard hasOutstandingPhysicalWork else { return }
        await withCheckedContinuation { continuation in
            idleWaiters.append(continuation)
        }
    }

    package func startExplicitRepositoryUpdate(
        repoId: UUID,
        attemptId: UUID
    ) -> RepositoryFactSourceUpdateAdmission {
        guard !isShuttingDown else { return .obsolete }
        guard let registration = registrationsByRepoId[repoId], let expectedOrigin = registration.expectedOrigin else {
            return .notApplicable
        }
        let settlement = RepositoryFactSourceUpdateSettlement(
            source: .remoteReferences,
            attemptId: attemptId
        )
        explicitUpdateAttemptsById[attemptId] = RemoteReferenceExplicitUpdateAttempt(
            repoId: repoId,
            topologyGeneration: registration.topologyGeneration,
            expectedOrigin: expectedOrigin,
            settlement: settlement
        )
        performanceAccumulator.increment(\.explicitAdmitted)
        explicitRepositoryIds.insert(repoId)
        if activeOperationsByRepoId[repoId] == nil {
            pendingRepositoryIds.insert(repoId)
        }
        admitPendingAttempts()
        rescheduleDeadline()
        return .accepted(settlement.lease)
    }
}

extension RemoteReferenceRefreshActor {
    func hasEffectiveInterest(repoId: UUID) -> Bool {
        demandedRepositoryIds.contains(repoId) || hasExplicitInterest(repoId: repoId)
    }

    func hasExplicitInterest(repoId: UUID) -> Bool {
        explicitUpdateAttemptsById.values.contains { $0.repoId == repoId }
    }

    func settleExplicitUpdateAttempts(
        matching physicalAttempt: RemoteReferenceAttempt,
        outcome: RepositoryFactSourceUpdateOutcome
    ) {
        var settledCount = 0
        for attemptId in explicitUpdateAttemptsById.keys {
            guard let attempt = explicitUpdateAttemptsById[attemptId],
                attempt.repoId == physicalAttempt.repoId,
                attempt.topologyGeneration == physicalAttempt.topologyGeneration,
                attempt.expectedOrigin == physicalAttempt.expectedOrigin
            else { continue }
            explicitUpdateAttemptsById.removeValue(forKey: attemptId)
            attempt.settlement.resolve(outcome)
            settledCount += 1
        }
        performanceAccumulator.recordExplicitSettlement(outcome, count: settledCount)
        flushPerformanceSnapshot()
        contractExplicitInterest(repoId: physicalAttempt.repoId)
    }

    func settleExplicitUpdateAttempts(
        repoId: UUID,
        outcome: RepositoryFactSourceUpdateOutcome
    ) {
        var settledCount = 0
        for attemptId in explicitUpdateAttemptsById.keys {
            guard let attempt = explicitUpdateAttemptsById[attemptId], attempt.repoId == repoId else { continue }
            explicitUpdateAttemptsById.removeValue(forKey: attemptId)
            attempt.settlement.resolve(outcome)
            settledCount += 1
        }
        performanceAccumulator.recordExplicitSettlement(outcome, count: settledCount)
        flushPerformanceSnapshot()
        contractExplicitInterest(repoId: repoId)
    }

    func settleAllExplicitUpdateAttempts(_ outcome: RepositoryFactSourceUpdateOutcome) {
        let attempts = explicitUpdateAttemptsById.values
        let settledCount = attempts.count
        explicitUpdateAttemptsById.removeAll(keepingCapacity: false)
        explicitRepositoryIds.removeAll(keepingCapacity: false)
        for attempt in attempts {
            attempt.settlement.resolve(outcome)
        }
        performanceAccumulator.recordExplicitSettlement(outcome, count: settledCount)
        flushPerformanceSnapshot()
    }

    func contractExplicitInterest(repoId: UUID) {
        guard !hasExplicitInterest(repoId: repoId) else { return }
        explicitRepositoryIds.remove(repoId)
        if !demandedRepositoryIds.contains(repoId) {
            pendingRepositoryIds.remove(repoId)
        }
    }
}
