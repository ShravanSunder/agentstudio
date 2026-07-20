import Foundation

struct GitLogicalDebtSnapshot: Equatable, Sendable {
    let queuedChangesetCount: Int
    let retryPendingCount: Int
    let logicalRunningCount: Int

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
        ]
    }
}

extension GitWorkingDirectoryProjector {
    func logicalDebtSnapshot() -> GitLogicalDebtSnapshot {
        GitLogicalDebtSnapshot(
            queuedChangesetCount: queuedLogicalDebtCount,
            retryPendingCount: retryPendingLogicalDebtCount,
            logicalRunningCount: runningLogicalDebtCount
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
