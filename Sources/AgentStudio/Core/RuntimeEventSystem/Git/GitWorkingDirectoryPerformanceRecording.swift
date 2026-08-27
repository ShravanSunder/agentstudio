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
    package var exactCleanBaselinePrepared: UInt64 = 0
    package var exactCleanBaselineAccepted: UInt64 = 0
    package var exactCleanBaselineRejected: UInt64 = 0
    package var exactCleanContinuityRenewed: UInt64 = 0
    package var exactCleanMutationInvalidated: UInt64 = 0
    package var continuityUncertaintyUnsupportedObservation: UInt64 = 0
    package var continuityUncertaintyRegistrationMissing: UInt64 = 0
    package var continuityUncertaintyRegistrationReplaced: UInt64 = 0
    package var continuityUncertaintyIdentityChanged: UInt64 = 0
    package var continuityUncertaintyMutationObserved: UInt64 = 0
    package var continuityUncertaintyEventStreamUncertain: UInt64 = 0
    package var continuityUncertaintyStreamStartFailed: UInt64 = 0
    package var continuityUncertaintyShutdown: UInt64 = 0
    package var exactFallbackAdmitted: UInt64 = 0
    package var exactFallbackCoalesced: UInt64 = 0
    package var avoidedPhysicalFactsRead: UInt64 = 0
    package var avoidedPhysicalDetailRead: UInt64 = 0
    package var pendingMaximum: UInt64 = 0
    package var runningMaximum: UInt64 = 0
    package var exactCleanAuthorityCurrent: UInt64 = 0
    package var exactCleanOldestCheckpointAgeMilliseconds: Double = 0

    package var eventCount: UInt64 {
        visibilityBatched + visibilityTierDeferred + visibilitySuperseded
            + visibilityAdmittedUncovered + admitted + eventPosted + snapshotEqual + suppressedInput
            + exactCleanBaselinePrepared + exactCleanBaselineAccepted + exactCleanBaselineRejected
            + exactCleanContinuityRenewed + exactCleanMutationInvalidated
            + continuityUncertaintyUnsupportedObservation + continuityUncertaintyRegistrationMissing
            + continuityUncertaintyRegistrationReplaced + continuityUncertaintyIdentityChanged
            + continuityUncertaintyMutationObserved + continuityUncertaintyEventStreamUncertain
            + continuityUncertaintyStreamStartFailed + continuityUncertaintyShutdown
            + exactFallbackAdmitted + exactFallbackCoalesced
            + avoidedPhysicalFactsRead + avoidedPhysicalDetailRead
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

    package mutating func recordExactCleanBaselinePrepared() {
        increment(\.exactCleanBaselinePrepared)
    }

    package mutating func recordExactCleanBaselineAccepted() {
        increment(\.exactCleanBaselineAccepted)
    }

    package mutating func recordExactCleanBaselineRejected() {
        increment(\.exactCleanBaselineRejected)
    }

    package mutating func recordExactCleanContinuityRenewed() {
        increment(\.exactCleanContinuityRenewed)
    }

    package mutating func recordExactCleanMutationInvalidated() {
        increment(\.exactCleanMutationInvalidated)
    }

    package mutating func recordExactFallbackAdmitted() {
        increment(\.exactFallbackAdmitted)
    }

    package mutating func recordExactFallbackCoalesced() {
        increment(\.exactFallbackCoalesced)
    }

    package mutating func recordAvoidedPhysicalFactsRead() {
        increment(\.avoidedPhysicalFactsRead)
    }

    package mutating func recordAvoidedPhysicalDetailRead() {
        increment(\.avoidedPhysicalDetailRead)
    }

    package mutating func recordContinuityUncertainty(_ reason: GitCleanContinuityFailureReason) {
        switch reason {
        case .unsupportedObservation:
            increment(\.continuityUncertaintyUnsupportedObservation)
        case .registrationMissing:
            increment(\.continuityUncertaintyRegistrationMissing)
        case .registrationReplaced:
            increment(\.continuityUncertaintyRegistrationReplaced)
        case .identityChanged:
            increment(\.continuityUncertaintyIdentityChanged)
        case .mutationObserved:
            increment(\.continuityUncertaintyMutationObserved)
        case .eventStreamUncertain:
            increment(\.continuityUncertaintyEventStreamUncertain)
        case .streamStartFailed:
            increment(\.continuityUncertaintyStreamStartFailed)
        case .shutdown:
            increment(\.continuityUncertaintyShutdown)
        }
    }

    package mutating func recordExactCleanContinuityState(
        authorityCount: Int,
        oldestCheckpointAgeMilliseconds: Double
    ) {
        snapshot.exactCleanAuthorityCurrent = UInt64(clamping: authorityCount)
        snapshot.exactCleanOldestCheckpointAgeMilliseconds =
            oldestCheckpointAgeMilliseconds.isFinite
            ? max(0, oldestCheckpointAgeMilliseconds)
            : 0
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
                "agentstudio.performance.git.aggregate.continuity.baseline.prepared.count": .int(
                    Int(clamping: snapshot.exactCleanBaselinePrepared)),
                "agentstudio.performance.git.aggregate.continuity.baseline.accepted.count": .int(
                    Int(clamping: snapshot.exactCleanBaselineAccepted)),
                "agentstudio.performance.git.aggregate.continuity.baseline.rejected.count": .int(
                    Int(clamping: snapshot.exactCleanBaselineRejected)),
                "agentstudio.performance.git.aggregate.continuity.renewed.count": .int(
                    Int(clamping: snapshot.exactCleanContinuityRenewed)),
                "agentstudio.performance.git.aggregate.continuity.mutation_invalidated.count": .int(
                    Int(clamping: snapshot.exactCleanMutationInvalidated)),
                "agentstudio.performance.git.aggregate.continuity.uncertainty.unsupported_observation.count": .int(
                    Int(clamping: snapshot.continuityUncertaintyUnsupportedObservation)),
                "agentstudio.performance.git.aggregate.continuity.uncertainty.registration_missing.count": .int(
                    Int(clamping: snapshot.continuityUncertaintyRegistrationMissing)),
                "agentstudio.performance.git.aggregate.continuity.uncertainty.registration_replaced.count": .int(
                    Int(clamping: snapshot.continuityUncertaintyRegistrationReplaced)),
                "agentstudio.performance.git.aggregate.continuity.uncertainty.identity_changed.count": .int(
                    Int(clamping: snapshot.continuityUncertaintyIdentityChanged)),
                "agentstudio.performance.git.aggregate.continuity.uncertainty.mutation_observed.count": .int(
                    Int(clamping: snapshot.continuityUncertaintyMutationObserved)),
                "agentstudio.performance.git.aggregate.continuity.uncertainty.event_stream_uncertain.count": .int(
                    Int(clamping: snapshot.continuityUncertaintyEventStreamUncertain)),
                "agentstudio.performance.git.aggregate.continuity.uncertainty.stream_start_failed.count": .int(
                    Int(clamping: snapshot.continuityUncertaintyStreamStartFailed)),
                "agentstudio.performance.git.aggregate.continuity.uncertainty.shutdown.count": .int(
                    Int(clamping: snapshot.continuityUncertaintyShutdown)),
                "agentstudio.performance.git.aggregate.continuity.fallback.admitted.count": .int(
                    Int(clamping: snapshot.exactFallbackAdmitted)),
                "agentstudio.performance.git.aggregate.continuity.fallback.coalesced.count": .int(
                    Int(clamping: snapshot.exactFallbackCoalesced)),
                "agentstudio.performance.git.aggregate.continuity.physical.fact_read_avoided.count": .int(
                    Int(clamping: snapshot.avoidedPhysicalFactsRead)),
                "agentstudio.performance.git.aggregate.continuity.physical.detail_read_avoided.count": .int(
                    Int(clamping: snapshot.avoidedPhysicalDetailRead)),
                "agentstudio.performance.git.aggregate.pending.maximum": .int(Int(clamping: snapshot.pendingMaximum)),
                "agentstudio.performance.git.aggregate.running.maximum": .int(Int(clamping: snapshot.runningMaximum)),
                "agentstudio.performance.git.aggregate.continuity.authority.current": .int(
                    Int(clamping: snapshot.exactCleanAuthorityCurrent)),
                "agentstudio.performance.git.aggregate.continuity.authority.oldest_checkpoint_age_ms": .double(
                    snapshot.exactCleanOldestCheckpointAgeMilliseconds),
            ]
        )
    }
}
