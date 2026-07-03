import Foundation

/// Status-compute backoff (circuit breaker): a worktree whose git status
/// repeatedly times out is refreshed on an exponential schedule instead of
/// per file-change event; change events arriving during backoff coalesce
/// into one deferred refresh at expiry. Split from the projector actor body
/// to keep it under the type/file length caps. Read-capacity contention uses
/// the separate short retry path below; it is not a breaker input.
extension GitWorkingDirectoryProjector {
    func deferChangesetIfStatusBackoffOpen(_ changeset: FileChangeset) -> Bool {
        guard openStatusBackoffWorktreeIds.contains(changeset.worktreeId) else { return false }
        coalesceDeferredStatusBackoffChangeset(changeset)
        return true
    }

    func coalesceDeferredStatusBackoffChangeset(_ changeset: FileChangeset) {
        let worktreeId = changeset.worktreeId
        guard let existing = deferredStatusBackoffChangesetByWorktreeId[worktreeId] else {
            deferredStatusBackoffChangesetByWorktreeId[worktreeId] = changeset
            return
        }
        deferredStatusBackoffChangesetByWorktreeId[worktreeId] = Self.newerChangeset(existing, changeset)
    }

    /// Opens (or advances) the per-worktree circuit breaker after a status
    /// compute times out. Quiesces the worktree by moving any in-flight/pending
    /// refresh into a single deferred changeset, then schedules an exponentially
    /// growing expiry.
    func openOrAdvanceStatusBackoff(
        for changeset: FileChangeset,
        reason: GitWorkingTreeStatusUnavailableReason
    ) {
        guard !isShuttingDown else { return }
        let worktreeId = changeset.worktreeId
        statusBackoffTasks.removeValue(forKey: worktreeId)?.cancel()

        let failureCount = (statusBackoffFailureCountByWorktreeId[worktreeId] ?? 0) + 1
        statusBackoffFailureCountByWorktreeId[worktreeId] = failureCount
        openStatusBackoffWorktreeIds.insert(worktreeId)

        // Quiesce: fold any pending compute plus the failed changeset into the
        // single deferred slot so nothing recomputes during the open window.
        if let pending = pendingByWorktreeId.removeValue(forKey: worktreeId) {
            coalesceDeferredStatusBackoffChangeset(pending)
        }
        coalesceDeferredStatusBackoffChangeset(changeset)

        let backoffDelay = refreshPolicy.statusFailureBackoffDelay(forConsecutiveFailureCount: failureCount)
        emitStatusBackoffTelemetry(
            worktreeId: worktreeId,
            open: true,
            reason: reason,
            backoffDelay: backoffDelay,
            attempt: failureCount
        )

        let delay = self.delay
        statusBackoffTasks[worktreeId] = Task { [weak self, delay, backoffDelay] in
            do {
                try await delay.wait(backoffDelay)
            } catch is CancellationError {
                return
            } catch {
                Self.logger.warning(
                    "Unexpected status-backoff sleep failure for worktree \(worktreeId.uuidString, privacy: .public): \(String(describing: error), privacy: .public)"
                )
                return
            }
            guard !Task.isCancelled else { return }
            await self?.expireStatusBackoff(worktreeId: worktreeId)
        }
    }

    /// Fires exactly one coalesced deferred refresh when the backoff window
    /// expires (half-open). The breaker closes only when that refresh succeeds
    /// via `resetStatusBackoff`; if it fails again the breaker re-opens with a
    /// longer window.
    func expireStatusBackoff(worktreeId: UUID) {
        statusBackoffTasks.removeValue(forKey: worktreeId)
        guard openStatusBackoffWorktreeIds.remove(worktreeId) != nil else { return }
        guard !isShuttingDown else {
            deferredStatusBackoffChangesetByWorktreeId.removeValue(forKey: worktreeId)
            return
        }
        guard !suppressedWorktreeIds.contains(worktreeId) else {
            deferredStatusBackoffChangesetByWorktreeId.removeValue(forKey: worktreeId)
            return
        }
        guard let deferredChangeset = deferredStatusBackoffChangesetByWorktreeId.removeValue(forKey: worktreeId) else {
            return
        }
        guard isCurrent(deferredChangeset) else { return }
        if pendingByWorktreeId[worktreeId] == nil {
            pendingByWorktreeId[worktreeId] = deferredChangeset
            admitPendingWorktrees()
        }
    }

    func deferChangesetIfCapacityRetryPending(_ changeset: FileChangeset) -> Bool {
        guard capacityRetryWorktreeIds.contains(changeset.worktreeId) else { return false }
        coalesceCapacityRetryChangeset(changeset)
        return true
    }

    func scheduleCapacityRetry(for changeset: FileChangeset) {
        guard !isShuttingDown else { return }
        let worktreeId = changeset.worktreeId
        capacityRetryWorktreeIds.insert(worktreeId)
        capacityRetryTasks.removeValue(forKey: worktreeId)?.cancel()
        coalesceCapacityRetryChangeset(changeset)

        let delay = self.delay
        let retryDelay = refreshPolicy.capacityRetryDelay(for: worktreeId)
        capacityRetryTasks[worktreeId] = Task { [weak self, delay, retryDelay] in
            do {
                try await delay.wait(retryDelay)
            } catch is CancellationError {
                return
            } catch {
                Self.logger.warning(
                    "Unexpected capacity-retry sleep failure for worktree \(worktreeId.uuidString, privacy: .public): \(String(describing: error), privacy: .public)"
                )
                return
            }
            guard !Task.isCancelled else { return }
            await self?.expireCapacityRetry(worktreeId: worktreeId)
        }
    }

    func expireCapacityRetry(worktreeId: UUID) {
        capacityRetryTasks.removeValue(forKey: worktreeId)
        guard capacityRetryWorktreeIds.remove(worktreeId) != nil else { return }
        guard !isShuttingDown else {
            pendingByWorktreeId.removeValue(forKey: worktreeId)
            return
        }
        guard !suppressedWorktreeIds.contains(worktreeId) else {
            pendingByWorktreeId.removeValue(forKey: worktreeId)
            return
        }
        guard let pendingChangeset = pendingByWorktreeId[worktreeId] else { return }
        guard isCurrent(pendingChangeset) else {
            pendingByWorktreeId.removeValue(forKey: worktreeId)
            return
        }
        admitPendingWorktrees()
    }

    func clearCapacityRetryState(worktreeId: UUID) {
        capacityRetryTasks.removeValue(forKey: worktreeId)?.cancel()
        capacityRetryWorktreeIds.remove(worktreeId)
    }

    private func coalesceCapacityRetryChangeset(_ changeset: FileChangeset) {
        let worktreeId = changeset.worktreeId
        guard let existing = pendingByWorktreeId[worktreeId] else {
            pendingByWorktreeId[worktreeId] = changeset
            return
        }
        pendingByWorktreeId[worktreeId] = Self.newerChangeset(existing, changeset)
    }

    /// Closes the breaker after a successful compute, clearing the failure count
    /// and any pending expiry, and emits a close fact when the breaker was armed.
    func resetStatusBackoff(worktreeId: UUID) {
        let hadFailures = statusBackoffFailureCountByWorktreeId.removeValue(forKey: worktreeId) != nil
        statusBackoffTasks.removeValue(forKey: worktreeId)?.cancel()
        let wasOpen = openStatusBackoffWorktreeIds.remove(worktreeId) != nil
        deferredStatusBackoffChangesetByWorktreeId.removeValue(forKey: worktreeId)
        guard hadFailures || wasOpen else { return }
        emitStatusBackoffTelemetry(worktreeId: worktreeId, open: false, reason: nil, backoffDelay: .zero, attempt: 0)
    }

    func clearStatusBackoffState(worktreeId: UUID) {
        statusBackoffTasks.removeValue(forKey: worktreeId)?.cancel()
        statusBackoffFailureCountByWorktreeId.removeValue(forKey: worktreeId)
        openStatusBackoffWorktreeIds.remove(worktreeId)
        deferredStatusBackoffChangesetByWorktreeId.removeValue(forKey: worktreeId)
    }

    func emitStatusBackoffTelemetry(
        worktreeId: UUID,
        open: Bool,
        reason: GitWorkingTreeStatusUnavailableReason?,
        backoffDelay: Duration,
        attempt: Int
    ) {
        guard let performanceTraceRecorder else { return }
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.worktree.id": .string(worktreeId.uuidString),
            "agentstudio.performance.git.backoff_open": .bool(open),
            "agentstudio.performance.git.backoff_ms": .double(
                AgentStudioPerformanceTraceRecorder.milliseconds(from: backoffDelay)
            ),
            "agentstudio.performance.git.backoff_attempt.count": .int(attempt),
            "agentstudio.performance.git.pending.count": .int(pendingByWorktreeId.count),
            "agentstudio.performance.git.running.count": .int(worktreeTasks.count),
        ]
        if let reason {
            attributes["agentstudio.performance.git.backoff.reason"] = .string(reason.rawValue)
        }
        performanceTraceRecorder.record(.gitBackoff, attributes: attributes)
    }

    nonisolated private static func newerChangeset(
        _ lhs: FileChangeset,
        _ rhs: FileChangeset
    ) -> FileChangeset {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp > rhs.timestamp ? lhs : rhs
        }
        return lhs.batchSeq >= rhs.batchSeq ? lhs : rhs
    }
}
