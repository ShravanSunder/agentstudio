import AgentStudioInfrastructure
import Foundation

extension GitWorkingDirectoryProjector {
    func handleAvailableStatusResult(
        _ statusSnapshot: GitWorkingTreeStatus,
        materialized: MaterializedGitStatus,
        changeset: FileChangeset,
        computeStart: ContinuousClock.Instant,
        scope: GitStatusScope,
        pathspecCount: Int
    ) async {
        let statusCompletion = envelopeClock.now
        let statusDuration = computeStart.duration(to: statusCompletion)
        consecutiveStatusFailureCountByWorktreeId.removeValue(forKey: changeset.worktreeId)
        performanceTraceRecorder?.recordDuration(
            .gitStatusComputed,
            duration: statusDuration,
            attributes: gitStatusCompletionTraceAttributes(
                for: changeset,
                unavailable: nil,
                context: GitStatusCompletionTraceContext(
                    scope: scope,
                    pathspecCount: pathspecCount,
                    statusCompletion: statusCompletion,
                    outcome: .completed,
                    consecutiveFailureCount: 0,
                    statusDuration: statusDuration
                )
            )
        )
        guard !Task.isCancelled, !isShuttingDown else { return }
        guard !suppressedWorktreeIds.contains(changeset.worktreeId) else { return }
        guard isCurrentForPublication(changeset) else { return }
        let currentStatusSnapshot = await prepareRemoteReferenceCurrentStatus(
            statusSnapshot,
            changeset: changeset
        )
        admissionStartedAtByWorktreeId.removeValue(forKey: changeset.worktreeId)
        clearCapacityRetryState(worktreeId: changeset.worktreeId)
        resetStatusBackoff(worktreeId: changeset.worktreeId)
        let previousAccepted = acceptedStatusBaseline(for: changeset.worktreeId)
        let currentAcceptedFacts = GitWorkingTreeStatusFacts(status: currentStatusSnapshot)
        let completeStatusChanged =
            previousAccepted.facts != currentAcceptedFacts
            || previousAccepted.detail != materialized.detail
        lastStatusEntriesByWorktreeId[changeset.worktreeId] = currentStatusSnapshot.entries
        lastAcceptedStatusFactsByWorktreeId[changeset.worktreeId] = currentAcceptedFacts
        acceptExactCleanAuthority(from: materialized, scope: scope, changeset: changeset)
        if let detail = materialized.detail {
            lastAcceptedLineDetailByWorktreeId[changeset.worktreeId] = detail
            if materialized.refreshedDetail {
                lastAcceptedLineDetailAtByWorktreeId[changeset.worktreeId] = deadlineClock.now
            }
        }

        let nextSnapshot = GitWorkingTreeSnapshot(
            worktreeId: changeset.worktreeId,
            repoId: changeset.repoId,
            rootPath: changeset.rootPath,
            summary: currentStatusSnapshot.summary,
            branch: currentStatusSnapshot.branch
        )
        let previousSnapshot = lastEmittedSnapshotByWorktreeId[changeset.worktreeId]
        let snapshotChanged = previousSnapshot != nextSnapshot
        if completeStatusChanged {
            resetAdaptiveCadence(worktreeId: changeset.worktreeId)
        } else {
            if pendingByWorktreeId[changeset.worktreeId] == nil {
                unchangedStatusResultCountByWorktreeId[changeset.worktreeId, default: 0] += 1
            }
        }
        if snapshotChanged {
            lastEmittedSnapshotByWorktreeId[changeset.worktreeId] = nextSnapshot
        } else {
            aggregatePerformance.increment(\.snapshotEqual)
            flushAggregatePerformanceSnapshotIfNeeded()
        }
        recordAutomaticCompletion(worktreeId: changeset.worktreeId, duty: statusDuration)

        await emitGitWorkingDirectoryEvent(
            worktreeId: changeset.worktreeId,
            repoId: changeset.repoId,
            event: .statusOutcome(
                GitStatusOutcomeFact(
                    worktreeId: changeset.worktreeId,
                    repoId: changeset.repoId,
                    outcome: .completed,
                    reason: nil,
                    consecutiveFailureCount: 0
                ))
        )
        if snapshotChanged {
            await emitGitWorkingDirectoryEvent(
                worktreeId: changeset.worktreeId,
                repoId: changeset.repoId,
                event: .snapshotChanged(snapshot: nextSnapshot)
            )
        }

        if let previousSnapshot,
            let nextBranch = currentStatusSnapshot.branch,
            previousSnapshot.branch != nextBranch
        {
            await emitGitWorkingDirectoryEvent(
                worktreeId: changeset.worktreeId,
                repoId: changeset.repoId,
                event: .branchChanged(
                    worktreeId: changeset.worktreeId,
                    repoId: changeset.repoId,
                    from: previousSnapshot.branch ?? "",
                    to: nextBranch
                )
            )
        }
    }

    private func acceptExactCleanAuthority(
        from materialized: MaterializedGitStatus,
        scope: GitStatusScope,
        changeset: FileChangeset
    ) {
        let authority = materialized.facts.exactCleanAuthority
        let worktreeId = changeset.worktreeId
        if scope == .full, let authority {
            exactCleanAuthorityByWorktreeId[worktreeId] = authority
        } else {
            exactCleanAuthorityByWorktreeId.removeValue(forKey: worktreeId)
        }
    }

    private func acceptedStatusBaseline(
        for worktreeId: UUID
    ) -> (facts: GitWorkingTreeStatusFacts?, detail: GitWorkingTreeLineDetail?) {
        (
            facts: lastAcceptedStatusFactsByWorktreeId[worktreeId],
            detail: lastAcceptedLineDetailByWorktreeId[worktreeId]
        )
    }
}
