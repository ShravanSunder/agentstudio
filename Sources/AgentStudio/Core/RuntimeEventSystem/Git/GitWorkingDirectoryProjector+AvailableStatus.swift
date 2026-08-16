import AgentStudioInfrastructure
import Foundation

extension GitWorkingDirectoryProjector {
    func handleAvailableStatusResult(
        _ statusSnapshot: GitWorkingTreeStatus,
        changeset: FileChangeset,
        computeStart: ContinuousClock.Instant,
        scope: GitStatusScope,
        pathspecCount: Int
    ) async {
        let statusCompletion = envelopeClock.now
        let statusDuration = computeStart.duration(to: statusCompletion)
        consecutiveStatusTimeoutCountByWorktreeId.removeValue(forKey: changeset.worktreeId)
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
                    consecutiveTimeoutCount: 0,
                    statusDuration: statusDuration
                )
            )
        )
        await emitGitWorkingDirectoryEvent(
            worktreeId: changeset.worktreeId,
            repoId: changeset.repoId,
            event: .statusOutcome(
                worktreeId: changeset.worktreeId,
                repoId: changeset.repoId,
                outcome: .completed,
                consecutiveTimeoutCount: 0
            )
        )
        guard !Task.isCancelled, !isShuttingDown else { return }
        guard !suppressedWorktreeIds.contains(changeset.worktreeId) else { return }
        guard isCurrent(changeset) else { return }
        admissionStartedAtByWorktreeId.removeValue(forKey: changeset.worktreeId)
        nilStatusRetryCountByWorktreeId.removeValue(forKey: changeset.worktreeId)
        clearCapacityRetryState(worktreeId: changeset.worktreeId)
        resetStatusBackoff(worktreeId: changeset.worktreeId)
        lastStatusEntriesByWorktreeId[changeset.worktreeId] = statusSnapshot.entries

        let nextSnapshot = GitWorkingTreeSnapshot(
            worktreeId: changeset.worktreeId,
            repoId: changeset.repoId,
            rootPath: changeset.rootPath,
            summary: statusSnapshot.summary,
            branch: statusSnapshot.branch
        )
        let previousSnapshot = lastEmittedSnapshotByWorktreeId[changeset.worktreeId]
        if previousSnapshot != nextSnapshot {
            lastEmittedSnapshotByWorktreeId[changeset.worktreeId] = nextSnapshot
            resetAdaptiveCadence(worktreeId: changeset.worktreeId)
            await emitGitWorkingDirectoryEvent(
                worktreeId: changeset.worktreeId,
                repoId: changeset.repoId,
                event: .snapshotChanged(snapshot: nextSnapshot)
            )
        } else {
            performanceTraceRecorder?.record(
                .gitSnapshotDedup,
                attributes: [
                    "agentstudio.worktree.id": .string(changeset.worktreeId.uuidString),
                    "agentstudio.performance.git.snapshot_dedup.count": .int(1),
                ]
            )
            if pendingByWorktreeId[changeset.worktreeId] == nil {
                unchangedStatusResultCountByWorktreeId[changeset.worktreeId, default: 0] += 1
            }
        }

        if let previousSnapshot,
            let nextBranch = statusSnapshot.branch,
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
        guard shouldCheckOrigin(for: changeset) else { return }
        await emitOriginResolutionIfChanged(changeset: changeset, statusSnapshot: statusSnapshot)
    }
}
