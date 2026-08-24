import AgentStudioInfrastructure

package struct GitWorkingDirectoryPerformanceSnapshot: Equatable, Sendable {
    package var visibilityBatched: UInt64 = 0
    package var visibilityTierDeferred: UInt64 = 0
    package var visibilitySuperseded: UInt64 = 0
    package var visibilityAdmittedUncovered: UInt64 = 0
    package var admitted: UInt64 = 0
    package var eventPosted: UInt64 = 0
    package var droppedSubscriber: UInt64 = 0
    package var snapshotEqual: UInt64 = 0
    package var suppressedInput: UInt64 = 0
    package var pendingMaximum: UInt64 = 0
    package var runningMaximum: UInt64 = 0

    package var eventCount: UInt64 {
        visibilityBatched + visibilityTierDeferred + visibilitySuperseded
            + visibilityAdmittedUncovered + admitted + eventPosted + snapshotEqual + suppressedInput
    }

    package var isEmpty: Bool { self == Self() }
}

package struct GitWorkingDirectoryPerformanceAccumulator: Sendable {
    private var snapshot = GitWorkingDirectoryPerformanceSnapshot()

    package init() {}

    package mutating func increment(
        _ keyPath: WritableKeyPath<GitWorkingDirectoryPerformanceSnapshot, UInt64>,
        by increment: Int = 1
    ) {
        guard increment > 0 else { return }
        let increment = UInt64(increment)
        let value = snapshot[keyPath: keyPath]
        snapshot[keyPath: keyPath] = value > UInt64.max - increment ? .max : value + increment
    }

    package mutating func recordPhysicalState(pending: Int, running: Int) {
        snapshot.pendingMaximum = max(snapshot.pendingMaximum, UInt64(clamping: pending))
        snapshot.runningMaximum = max(snapshot.runningMaximum, UInt64(clamping: running))
    }

    package mutating func takeSnapshot() -> GitWorkingDirectoryPerformanceSnapshot {
        defer { snapshot = GitWorkingDirectoryPerformanceSnapshot() }
        return snapshot
    }

    package var eventCount: UInt64 { snapshot.eventCount }
}

extension AgentStudioPerformanceTraceRecorder {
    package func recordGitWorkingDirectoryPerformanceSnapshot(
        _ snapshot: GitWorkingDirectoryPerformanceSnapshot
    ) {
        guard !snapshot.isEmpty else { return }
        record(
            .gitAggregate,
            attributes: [
                "agentstudio.performance.git.aggregate.visibility_batched.count": .int(
                    Int(clamping: snapshot.visibilityBatched)),
                "agentstudio.performance.git.aggregate.visibility_tier_deferred.count": .int(
                    Int(clamping: snapshot.visibilityTierDeferred)),
                "agentstudio.performance.git.aggregate.visibility_superseded.count": .int(
                    Int(clamping: snapshot.visibilitySuperseded)),
                "agentstudio.performance.git.aggregate.visibility_admitted_uncovered.count": .int(
                    Int(clamping: snapshot.visibilityAdmittedUncovered)),
                "agentstudio.performance.git.aggregate.admitted.count": .int(Int(clamping: snapshot.admitted)),
                "agentstudio.performance.git.aggregate.event_posted.count": .int(Int(clamping: snapshot.eventPosted)),
                "agentstudio.performance.git.aggregate.dropped_subscriber.count": .int(
                    Int(clamping: snapshot.droppedSubscriber)),
                "agentstudio.performance.git.aggregate.snapshot_equal.count": .int(
                    Int(clamping: snapshot.snapshotEqual)),
                "agentstudio.performance.git.aggregate.suppressed_input.count": .int(
                    Int(clamping: snapshot.suppressedInput)),
                "agentstudio.performance.git.aggregate.pending.maximum": .int(Int(clamping: snapshot.pendingMaximum)),
                "agentstudio.performance.git.aggregate.running.maximum": .int(Int(clamping: snapshot.runningMaximum)),
            ]
        )
    }
}
