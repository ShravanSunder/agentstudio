import Foundation

extension ForgeActor {
    func repositoryFactRefreshRepoIds() -> Set<UUID> {
        demandedRepoIds().union(explicitUpdateAttemptsById.values.map(\.repoId))
    }

    func hasExplicitUpdateInterest(repoId: UUID) -> Bool {
        explicitUpdateAttemptsById.values.contains { $0.repoId == repoId }
    }

    func explicitAttemptIds(repoId: UUID) -> Set<UUID> {
        Set(
            explicitUpdateAttemptsById.compactMap { attemptId, attempt in
                attempt.repoId == repoId ? attemptId : nil
            })
    }

    package func refresh(repo repoId: UUID, correlationId: UUID? = nil) async {
        defer { flushPerformanceSnapshot() }
        await requestRefreshIfDemanded(repoId: repoId, trigger: .manual, correlationId: correlationId)
        rescheduleDeadline()
    }

    package func startExplicitRepositoryUpdate(
        repoId: UUID,
        attemptId: UUID
    ) async -> RepositoryFactSourceUpdateAdmission {
        defer { flushPerformanceSnapshot() }
        guard !isShuttingDown else { return .obsolete }
        guard let state = refreshStateByRepoId[repoId], let origin = state.origin else {
            return .notApplicable
        }
        let branches = representedBranches(repoId: repoId)
        guard !branches.isEmpty else { return .notApplicable }

        let settlement = RepositoryFactSourceUpdateSettlement(source: .forge, attemptId: attemptId)
        explicitUpdateAttemptsById[attemptId] = ExplicitRepositoryUpdateAttempt(
            repoId: repoId,
            generation: state.generation,
            origin: origin,
            branches: branches,
            settlement: settlement
        )
        performanceAccumulator.recordExplicitAdmission()
        let requestedSignature = ProviderRequestSignature(origin: origin, demandedBranches: branches)
        if state.activeRequestSignature != requestedSignature {
            await requestRefreshIfDemanded(repoId: repoId, trigger: .manual, correlationId: nil)
        }
        rescheduleDeadline()
        return .accepted(settlement.lease)
    }
}
