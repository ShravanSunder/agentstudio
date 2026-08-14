import Foundation

enum GitRefreshTriggerSource: String, Sendable {
    case registration
    case filesystemChange = "filesystem_change"
    case periodic
    case visibilityChange = "visibility_change"
    case retry
}

struct GitRefreshAttributionState {
    var triggerSourceByWorktreeId: [UUID: GitRefreshTriggerSource] = [:]
    var requestSequenceByWorktreeId: [UUID: UInt64] = [:]
    var admittedDemandClassByWorktreeId: [UUID: String] = [:]
    var admittedCadenceTierByWorktreeId: [UUID: String] = [:]
    var admittedTriggerSourceByWorktreeId: [UUID: GitRefreshTriggerSource] = [:]
    var nextRequestSequence: UInt64 = 0
}

extension GitWorkingDirectoryProjector {
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
        immediateRefreshWorktreeIds.insert(worktreeId)
        if isExplicit {
            explicitRefreshWorktreeIds.insert(worktreeId)
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
