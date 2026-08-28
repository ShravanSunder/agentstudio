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

extension GitWorkingDirectoryProjector {
    func recordRequiredIntent(
        changeset: FileChangeset,
        triggerSource: GitRefreshTriggerSource,
        isExplicit: Bool = false
    ) {
        guard isExplicit || triggerSource == .filesystemChange || triggerSource == .remoteReferenceRefresh else {
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
        isExplicit: Bool = false
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
        enqueueImmediateRefresh(changeset, triggerSource: triggerSource, isExplicit: isExplicit)
    }

    func enqueueImmediateRefresh(
        _ changeset: FileChangeset,
        triggerSource: GitRefreshTriggerSource,
        isExplicit: Bool = false
    ) {
        let worktreeId = changeset.worktreeId
        recordRequiredIntent(
            changeset: changeset,
            triggerSource: triggerSource,
            isExplicit: isExplicit
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
