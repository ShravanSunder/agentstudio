import Foundation

/// Performance telemetry helpers split from the projector actor body so git
/// performance records can stay per-worktree without growing the actor body.
extension GitWorkingDirectoryProjector {
    func recordPeriodicRefreshTickTelemetry(
        enqueuedWorktreeIds: [UUID],
        registeredCount: Int,
        pendingCount: Int,
        tick: UInt64
    ) {
        guard let performanceTraceRecorder else { return }
        for worktreeId in enqueuedWorktreeIds {
            performanceTraceRecorder.record(
                .gitTick,
                attributes: [
                    "agentstudio.worktree.id": .string(worktreeId.uuidString),
                    "agentstudio.performance.git.enqueued.count": .int(1),
                    "agentstudio.performance.git.registered.count": .int(registeredCount),
                    "agentstudio.performance.git.pending.count": .int(pendingCount),
                    "agentstudio.performance.git.tick.count": .int(Int(tick)),
                ]
            )
        }
    }

    func recordGitAdmissionTelemetry(
        admittedWorktreeIds: [UUID],
        availableSlots: Int
    ) {
        guard let performanceTraceRecorder else { return }
        for worktreeId in admittedWorktreeIds {
            performanceTraceRecorder.record(
                .gitAdmission,
                attributes: [
                    "agentstudio.worktree.id": .string(worktreeId.uuidString),
                    "agentstudio.performance.git.admitted.count": .int(1),
                    "agentstudio.performance.git.pending.count": .int(pendingByWorktreeId.count),
                    "agentstudio.performance.git.running.count": .int(worktreeTasks.count),
                    "agentstudio.performance.git.available_slot.count": .int(availableSlots),
                ]
            )
        }
    }
}
