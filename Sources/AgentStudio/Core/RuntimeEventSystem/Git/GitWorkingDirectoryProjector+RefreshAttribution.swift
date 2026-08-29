import Foundation

enum GitRefreshTriggerSource: String, Sendable {
    case registration
    case filesystemChange = "filesystem_change"
    case periodic
    case visibilityChange = "visibility_change"
    case remoteReferenceRefresh = "remote_reference_refresh"
    case retry
}

struct GitRefreshAttributionState {
    var triggerSourceByWorktreeId: [UUID: GitRefreshTriggerSource] = [:]
    var requestSequenceByWorktreeId: [UUID: UInt64] = [:]
    var admittedDemandClassByWorktreeId: [UUID: String] = [:]
    var admittedCadenceTierByWorktreeId: [UUID: String] = [:]
    var admittedTriggerSourceByWorktreeId: [UUID: GitRefreshTriggerSource] = [:]
    var pendingRequiredIntentGenerationByWorktreeId: [UUID: UInt64] = [:]
    var admittedRequiredIntentGenerationByWorktreeId: [UUID: UInt64] = [:]
    var nextRequestSequence: UInt64 = 0
    var nextRequiredIntentGeneration: UInt64 = 0
}

struct GitExplicitRepositoryUpdateAttempt {
    let repositoryId: UUID
    let settlement: RepositoryFactSourceUpdateSettlement
    var requiredIntentGenerationByWorktreeId: [UUID: UInt64]
    var outcomesByWorktreeId: [UUID: RepositoryFactSourceUpdateOutcome] = [:]
}

extension GitWorkingDirectoryProjector {
    package func startExplicitRepositoryUpdate(
        repoId: UUID,
        attemptId: UUID
    ) -> RepositoryFactSourceUpdateAdmission {
        guard !isShuttingDown else { return .obsolete }
        let worktreeIds = repoIdByWorktreeId.compactMap { worktreeId, candidateRepoId in
            candidateRepoId == repoId && registeredContext(for: worktreeId) != nil ? worktreeId : nil
        }
        guard !worktreeIds.isEmpty else { return .notApplicable }

        let settlement = RepositoryFactSourceUpdateSettlement(
            source: .localGit,
            attemptId: attemptId
        )
        var requiredIntentGenerationByWorktreeId: [UUID: UInt64] = [:]
        for worktreeId in worktreeIds.sorted(by: { $0.uuidString < $1.uuidString }) {
            if worktreeTasks[worktreeId] != nil,
                refreshAttribution.admittedDemandClassByWorktreeId[worktreeId] == "explicit",
                let admittedGeneration =
                    refreshAttribution.admittedRequiredIntentGenerationByWorktreeId[worktreeId]
            {
                requiredIntentGenerationByWorktreeId[worktreeId] = admittedGeneration
                continue
            }

            enqueueImmediateRefreshIfRegistered(
                worktreeId: worktreeId,
                triggerSource: .visibilityChange,
                isExplicit: true
            )
            guard
                let requiredGeneration =
                    refreshAttribution.pendingRequiredIntentGenerationByWorktreeId[worktreeId]
                    ?? refreshAttribution.admittedRequiredIntentGenerationByWorktreeId[worktreeId]
            else {
                continue
            }
            requiredIntentGenerationByWorktreeId[worktreeId] = requiredGeneration
        }

        guard requiredIntentGenerationByWorktreeId.count == worktreeIds.count else {
            settlement.resolve(.obsolete)
            return .obsolete
        }
        explicitRepositoryUpdateAttemptsById[attemptId] = GitExplicitRepositoryUpdateAttempt(
            repositoryId: repoId,
            settlement: settlement,
            requiredIntentGenerationByWorktreeId: requiredIntentGenerationByWorktreeId
        )
        recordExplicitUpdateAdmissionTelemetry()
        return .accepted(settlement.lease)
    }

    func settleExplicitRepositoryUpdateTarget(
        worktreeId: UUID,
        requiredIntentGeneration: UInt64?,
        outcome: RepositoryFactSourceUpdateOutcome
    ) {
        for attemptId in explicitRepositoryUpdateAttemptsById.keys {
            guard var attempt = explicitRepositoryUpdateAttemptsById[attemptId],
                let expectedGeneration = attempt.requiredIntentGenerationByWorktreeId[worktreeId],
                requiredIntentGeneration == nil || expectedGeneration == requiredIntentGeneration,
                attempt.outcomesByWorktreeId[worktreeId] == nil
            else { continue }
            attempt.outcomesByWorktreeId[worktreeId] = outcome
            guard attempt.outcomesByWorktreeId.count == attempt.requiredIntentGenerationByWorktreeId.count else {
                explicitRepositoryUpdateAttemptsById[attemptId] = attempt
                continue
            }
            explicitRepositoryUpdateAttemptsById.removeValue(forKey: attemptId)
            let compositeOutcome = Self.compositeExplicitRepositoryUpdateOutcome(
                attempt.outcomesByWorktreeId.values)
            attempt.settlement.resolve(compositeOutcome)
            recordExplicitUpdateSettlementTelemetry(compositeOutcome)
        }
    }

    func settleCompletedExplicitRepositoryUpdateTarget(worktreeId: UUID) {
        guard
            let requiredIntentGeneration =
                refreshAttribution.admittedRequiredIntentGenerationByWorktreeId[worktreeId]
        else { return }
        settleExplicitRepositoryUpdateTarget(
            worktreeId: worktreeId,
            requiredIntentGeneration: requiredIntentGeneration,
            outcome: .completed
        )
    }

    func settleAllExplicitRepositoryUpdates(_ outcome: RepositoryFactSourceUpdateOutcome) {
        let attempts = explicitRepositoryUpdateAttemptsById.values
        explicitRepositoryUpdateAttemptsById.removeAll(keepingCapacity: false)
        for attempt in attempts {
            attempt.settlement.resolve(outcome)
            recordExplicitUpdateSettlementTelemetry(outcome)
        }
    }

    private nonisolated static func compositeExplicitRepositoryUpdateOutcome(
        _ outcomes: Dictionary<UUID, RepositoryFactSourceUpdateOutcome>.Values
    ) -> RepositoryFactSourceUpdateOutcome {
        if outcomes.contains(.failed) { return .failed }
        if outcomes.contains(.obsolete) { return .obsolete }
        if outcomes.contains(.cancelled) { return .cancelled }
        return .completed
    }

    func recordRequiredIntent(
        changeset: FileChangeset,
        triggerSource: GitRefreshTriggerSource,
        isExplicit: Bool = false,
        isRequiredForCorrectness: Bool = false
    ) {
        guard
            isExplicit || isRequiredForCorrectness || triggerSource == .filesystemChange
                || triggerSource == .remoteReferenceRefresh
        else {
            return
        }
        let worktreeId = changeset.worktreeId
        refreshAttribution.nextRequiredIntentGeneration &+= 1
        refreshAttribution.pendingRequiredIntentGenerationByWorktreeId[worktreeId] =
            refreshAttribution.nextRequiredIntentGeneration
    }

    func hasRequiredIntent(worktreeId: UUID) -> Bool {
        refreshAttribution.pendingRequiredIntentGenerationByWorktreeId[worktreeId] != nil
            || refreshAttribution.admittedRequiredIntentGenerationByWorktreeId[worktreeId] != nil
    }

    func admitPendingRequiredIntent(worktreeId: UUID) {
        guard
            let pendingGeneration =
                refreshAttribution.pendingRequiredIntentGenerationByWorktreeId.removeValue(forKey: worktreeId)
        else { return }
        refreshAttribution.admittedRequiredIntentGenerationByWorktreeId[worktreeId] = max(
            refreshAttribution.admittedRequiredIntentGenerationByWorktreeId[worktreeId] ?? 0,
            pendingGeneration
        )
    }

    func completeAdmittedRequiredIntent(worktreeId: UUID) {
        guard
            refreshAttribution.admittedRequiredIntentGenerationByWorktreeId.removeValue(forKey: worktreeId) != nil
        else { return }
        guard !isAutomaticEligible(worktreeId: worktreeId), !hasRequiredIntent(worktreeId: worktreeId) else {
            return
        }
        contractInactiveAutomaticState(worktreeId: worktreeId, preservesRequiredIntent: false)
        rescheduleDeadlineTask()
        recordLogicalDebtSnapshotIfChanged()
    }

    func clearRequiredIntent(worktreeId: UUID) {
        refreshAttribution.pendingRequiredIntentGenerationByWorktreeId.removeValue(forKey: worktreeId)
        refreshAttribution.admittedRequiredIntentGenerationByWorktreeId.removeValue(forKey: worktreeId)
    }

    func enqueueImmediateRefreshIfRegistered(
        worktreeId: UUID,
        triggerSource: GitRefreshTriggerSource = .visibilityChange,
        isExplicit: Bool = false,
        isRequiredForCorrectness: Bool = false
    ) {
        guard !suppressedWorktreeIds.contains(worktreeId) else { return }
        guard let context = registeredContext(for: worktreeId) else { return }

        let nextBatchSeq = (nextPeriodicBatchSeqByWorktreeId[worktreeId] ?? 0) + 1
        nextPeriodicBatchSeqByWorktreeId[worktreeId] = nextBatchSeq
        let changeset = FileChangeset(
            worktreeId: worktreeId,
            repoId: context.repoId,
            rootPath: context.rootPath,
            paths: [],
            containsGitInternalChanges: true,
            timestamp: envelopeClock.now,
            batchSeq: nextBatchSeq
        )
        enqueueImmediateRefresh(
            changeset,
            triggerSource: triggerSource,
            isExplicit: isExplicit,
            isRequiredForCorrectness: isRequiredForCorrectness
        )
    }

    func enqueueImmediateRefresh(
        _ changeset: FileChangeset,
        triggerSource: GitRefreshTriggerSource,
        isExplicit: Bool = false,
        isRequiredForCorrectness: Bool = false
    ) {
        let worktreeId = changeset.worktreeId
        recordRequiredIntent(
            changeset: changeset,
            triggerSource: triggerSource,
            isExplicit: isExplicit,
            isRequiredForCorrectness: isRequiredForCorrectness
        )
        immediateRefreshWorktreeIds.insert(worktreeId)
        if isExplicit {
            explicitRefreshWorktreeIds.insert(worktreeId)
            exactCleanAuthorityByWorktreeId.removeValue(forKey: worktreeId)
        }
        guard !deferChangesetIfStatusBackoffOpen(changeset) else { return }
        guard !deferChangesetIfCapacityRetryPending(changeset) else { return }
        pendingByWorktreeId[worktreeId] = Self.mergeChangesets(
            pendingByWorktreeId[worktreeId],
            with: changeset
        )
        refreshAttribution.triggerSourceByWorktreeId[worktreeId] = triggerSource
        if coalescingWorktreeIds.contains(worktreeId) {
            worktreeTasks[worktreeId]?.cancel()
        }
        admitPendingWorktrees()
    }
}
