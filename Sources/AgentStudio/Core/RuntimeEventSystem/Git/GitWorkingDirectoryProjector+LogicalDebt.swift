import AgentStudioInfrastructure
import Foundation

struct GitLogicalDebtSnapshot: Equatable, Sendable {
    let queuedChangesetCount: Int
    let retryPendingCount: Int
    let logicalRunningCount: Int
    let futureAutomaticCount: Int
    let futureFailureCount: Int
    let readyPendingCount: Int
    let capacityPendingCount: Int
    let activeFollowUpCount: Int
    let unclassifiedPendingCount: Int
    let overdueDeadlineCount: Int
    let oldestPreparationTimestamp: ContinuousClock.Instant?
    let nextDeadline: Duration?
    let oldestPreparationMilliseconds: Double
    let nextDeadlineMilliseconds: Double

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.queuedChangesetCount == rhs.queuedChangesetCount
            && lhs.retryPendingCount == rhs.retryPendingCount
            && lhs.logicalRunningCount == rhs.logicalRunningCount
            && lhs.futureAutomaticCount == rhs.futureAutomaticCount
            && lhs.futureFailureCount == rhs.futureFailureCount
            && lhs.readyPendingCount == rhs.readyPendingCount
            && lhs.capacityPendingCount == rhs.capacityPendingCount
            && lhs.activeFollowUpCount == rhs.activeFollowUpCount
            && lhs.unclassifiedPendingCount == rhs.unclassifiedPendingCount
            && lhs.overdueDeadlineCount == rhs.overdueDeadlineCount
            && lhs.oldestPreparationTimestamp == rhs.oldestPreparationTimestamp
            && lhs.nextDeadline == rhs.nextDeadline
    }

    var logicalPendingCount: Int {
        queuedChangesetCount + retryPendingCount
    }

    var logicalDebtCount: Int {
        logicalPendingCount + logicalRunningCount
    }

    var traceAttributes: [String: AgentStudioTraceValue] {
        [
            "agentstudio.performance.git.logical_pending.count": .int(logicalPendingCount),
            "agentstudio.performance.git.retry_pending.count": .int(retryPendingCount),
            "agentstudio.performance.git.logical_running.count": .int(logicalRunningCount),
            "agentstudio.performance.git.logical_debt.count": .int(logicalDebtCount),
            "agentstudio.performance.git.future_automatic.count": .int(futureAutomaticCount),
            "agentstudio.performance.git.future_failure.count": .int(futureFailureCount),
            "agentstudio.performance.git.ready_pending.count": .int(readyPendingCount),
            "agentstudio.performance.git.capacity_pending.count": .int(capacityPendingCount),
            "agentstudio.performance.git.active_follow_up.count": .int(activeFollowUpCount),
            "agentstudio.performance.git.unclassified_pending.count": .int(unclassifiedPendingCount),
            "agentstudio.performance.git.overdue_deadline.count": .int(overdueDeadlineCount),
            "agentstudio.performance.git.oldest_preparation_ms": .double(oldestPreparationMilliseconds),
            "agentstudio.performance.git.next_deadline_ms": .double(nextDeadlineMilliseconds),
        ]
    }
}

extension GitWorkingDirectoryProjector {
    func logicalDebtSnapshot() -> GitLogicalDebtSnapshot {
        let deadlineNow = deadlineClock.now
        let futureAutomaticWorktreeIds = Set(
            automaticRefreshDeadlineByWorktreeId.compactMap { worktreeId, deadline in
                deadline > deadlineNow ? worktreeId : nil
            })
        let futureFailureWorktreeIds = Set(
            statusFailureDeadlineByWorktreeId.compactMap { worktreeId, deadline in
                deadline > deadlineNow ? worktreeId : nil
            })
        let overdueDeadlineCount = [
            automaticRefreshDeadlineByWorktreeId,
            statusFailureDeadlineByWorktreeId,
            capacityFallbackDeadlineByWorktreeId,
        ].reduce(into: 0) { count, deadlines in
            count += deadlines.values.count { $0 <= deadlineNow }
        }

        var readyPendingCount = 0
        var capacityPendingCount = 0
        var activeFollowUpCount = 0
        var unclassifiedPendingCount = 0
        for worktreeId in pendingByWorktreeId.keys {
            if capacityRetryWorktreeIds.contains(worktreeId) {
                capacityPendingCount += 1
            } else if worktreeTasks[worktreeId] != nil {
                activeFollowUpCount += 1
            } else if futureFailureWorktreeIds.contains(worktreeId) {
                continue
            } else if futureAutomaticWorktreeIds.contains(worktreeId),
                !isDemandEligible(worktreeId: worktreeId)
            {
                continue
            } else if isDemandEligible(worktreeId: worktreeId) {
                readyPendingCount += 1
            } else {
                unclassifiedPendingCount += 1
            }
        }

        let nextDeadline = [
            automaticRefreshDeadlineByWorktreeId.values,
            statusFailureDeadlineByWorktreeId.values,
            capacityFallbackDeadlineByWorktreeId.values,
        ].flatMap { $0 }.filter { $0 > deadlineNow }.min()
        let oldestPreparationTimestamp = pendingByWorktreeId.values.map(\.timestamp).min()
        let oldestPreparationAge =
            oldestPreparationTimestamp.map {
                max(.zero, $0.duration(to: envelopeClock.now))
            } ?? .zero

        return GitLogicalDebtSnapshot(
            queuedChangesetCount: queuedLogicalDebtCount,
            retryPendingCount: retryPendingLogicalDebtCount,
            logicalRunningCount: runningLogicalDebtCount,
            futureAutomaticCount: futureAutomaticWorktreeIds.count,
            futureFailureCount: futureFailureWorktreeIds.count,
            readyPendingCount: readyPendingCount,
            capacityPendingCount: capacityPendingCount,
            activeFollowUpCount: activeFollowUpCount,
            unclassifiedPendingCount: unclassifiedPendingCount,
            overdueDeadlineCount: overdueDeadlineCount,
            oldestPreparationTimestamp: oldestPreparationTimestamp,
            nextDeadline: nextDeadline,
            oldestPreparationMilliseconds: AgentStudioPerformanceTraceRecorder.milliseconds(
                from: oldestPreparationAge),
            nextDeadlineMilliseconds: nextDeadline.map {
                AgentStudioPerformanceTraceRecorder.milliseconds(from: max(.zero, $0 - deadlineNow))
            } ?? 0
        )
    }

    func recordLogicalDebtSnapshotIfChanged() {
        guard performanceTraceRecorder?.isEnabled == true else { return }
        let snapshot = logicalDebtSnapshot()
        guard snapshot != lastRecordedLogicalDebtSnapshot else { return }
        lastRecordedLogicalDebtSnapshot = snapshot
        performanceTraceRecorder?.record(
            .gitLogicalDebt,
            attributes: snapshot.traceAttributes
        )
    }
}
