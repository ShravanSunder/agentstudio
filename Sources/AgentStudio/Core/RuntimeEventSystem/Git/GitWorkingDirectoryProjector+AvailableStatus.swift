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
        admissionStartedAtByWorktreeId.removeValue(forKey: changeset.worktreeId)
        clearCapacityRetryState(worktreeId: changeset.worktreeId)
        resetStatusBackoff(worktreeId: changeset.worktreeId)
        lastStatusEntriesByWorktreeId[changeset.worktreeId] = statusSnapshot.entries
        lastAcceptedStatusFactsByWorktreeId[changeset.worktreeId] = materialized.facts
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
            summary: statusSnapshot.summary,
            branch: statusSnapshot.branch
        )
        let previousSnapshot = lastEmittedSnapshotByWorktreeId[changeset.worktreeId]
        let snapshotChanged = previousSnapshot != nextSnapshot
        if snapshotChanged {
            lastEmittedSnapshotByWorktreeId[changeset.worktreeId] = nextSnapshot
            resetAdaptiveCadence(worktreeId: changeset.worktreeId)
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
