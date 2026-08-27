import AgentStudioInfrastructure
import Foundation

enum GitVisibilityAdmissionOutcome: String, Sendable {
    case batched
    case tierDeferred = "tier_deferred"
    case superseded
    case admittedUncovered = "admitted_uncovered"
}

struct GitStatusCompletionTraceContext {
    let scope: GitWorkingDirectoryProjector.GitStatusScope
    let pathspecCount: Int
    let statusCompletion: ContinuousClock.Instant
    let outcome: GitStatusOutcome
    let consecutiveFailureCount: Int
    let statusDuration: Duration
}

/// Performance telemetry helpers split from the projector actor body so git
/// performance records can stay per-worktree without growing the actor body.
extension GitWorkingDirectoryProjector {
    func gitStatusCompletionTraceAttributes(
        for changeset: FileChangeset,
        unavailable: GitWorkingTreeStatusUnavailable?,
        context: GitStatusCompletionTraceContext
    ) -> [String: AgentStudioTraceValue] {
        var attributes = gitStatusTraceAttributes(
            for: changeset,
            unavailable: unavailable,
            scope: context.scope,
            pathspecCount: context.pathspecCount
        )
        attributes["agentstudio.performance.git.status.last_outcome"] = .string(context.outcome.rawValue)
        attributes["agentstudio.performance.git.status.consecutive_failure.count"] = .int(
            context.consecutiveFailureCount
        )
        attributes["agentstudio.performance.git.status.duration_ms"] = .double(
            AgentStudioPerformanceTraceRecorder.milliseconds(from: context.statusDuration)
        )
        if let admissionStartedAt = admissionStartedAtByWorktreeId[changeset.worktreeId] {
            attributes["agentstudio.performance.git.admission_to_status.elapsed_ms"] = .double(
                AgentStudioPerformanceTraceRecorder.milliseconds(
                    from: admissionStartedAt.duration(to: context.statusCompletion)
                )
            )
        }
        return attributes
    }

    func recordVisibilityAdmissionTelemetry(
        worktreeIds: Set<UUID>,
        outcome: GitVisibilityAdmissionOutcome
    ) {
        let keyPath: WritableKeyPath<GitWorkingDirectoryPerformanceSnapshot, UInt64>
        switch outcome {
        case .batched: keyPath = \.visibilityBatched
        case .tierDeferred: keyPath = \.visibilityTierDeferred
        case .superseded: keyPath = \.visibilitySuperseded
        case .admittedUncovered: keyPath = \.visibilityAdmittedUncovered
        }
        aggregatePerformance.increment(keyPath, by: worktreeIds.count)
        recordAggregatePhysicalState()
        flushAggregatePerformanceSnapshotIfNeeded()
    }

    func recordGitAdmissionTelemetry(
        admittedWorktreeIds: [UUID],
        availableSlots: Int
    ) {
        aggregatePerformance.increment(\.admitted, by: admittedWorktreeIds.count)
        aggregatePerformance.recordPhysicalState(
            pending: pendingByWorktreeId.count,
            running: worktreeTasks.count
        )
        _ = availableSlots
        flushAggregatePerformanceSnapshotIfNeeded()
    }

    func recordAggregatePhysicalState() {
        aggregatePerformance.recordPhysicalState(
            pending: pendingByWorktreeId.count,
            running: worktreeTasks.count
        )
    }

    func recordExactCleanBaselinePreparedTelemetry() {
        aggregatePerformance.recordExactCleanBaselinePrepared()
    }

    func recordExactCleanBaselineRejectedTelemetry() {
        aggregatePerformance.recordExactCleanBaselineRejected()
        flushAggregatePerformanceSnapshotIfNeeded()
    }

    func recordExactCleanBaselineAcceptedTelemetry() {
        aggregatePerformance.recordExactCleanBaselineAccepted()
        flushAggregatePerformanceSnapshotIfNeeded()
    }

    func recordExactCleanContinuityRenewedTelemetry() {
        aggregatePerformance.recordExactCleanContinuityRenewed()
        aggregatePerformance.recordAvoidedPhysicalFactsRead()
        aggregatePerformance.recordAvoidedPhysicalDetailRead()
        flushAggregatePerformanceSnapshotIfNeeded()
    }

    func recordExactCleanMutationInvalidatedTelemetry() {
        aggregatePerformance.recordExactCleanMutationInvalidated()
        flushAggregatePerformanceSnapshotIfNeeded()
    }

    func recordContinuityUncertaintyTelemetry(
        _ reason: GitCleanContinuityFailureReason
    ) {
        aggregatePerformance.recordContinuityUncertainty(reason)
    }

    func recordExactFallbackTelemetry(admitted: Bool) {
        if admitted {
            aggregatePerformance.recordExactFallbackAdmitted()
        } else {
            aggregatePerformance.recordExactFallbackCoalesced()
        }
        flushAggregatePerformanceSnapshotIfNeeded()
    }

    func recordAvoidedPhysicalDetailReadTelemetry() {
        aggregatePerformance.recordAvoidedPhysicalDetailRead()
        flushAggregatePerformanceSnapshotIfNeeded()
    }

    func flushAggregatePerformanceSnapshotIfNeeded() {
        guard aggregatePerformance.eventCount >= AppPolicies.GitRefresh.telemetryFlushEventCount else { return }
        flushAggregatePerformanceSnapshot()
    }

    func flushAggregatePerformanceSnapshot() {
        recordExactCleanContinuityState()
        let snapshot = aggregatePerformance.takeSnapshot()
        guard !snapshot.isEmpty else { return }
        performanceTraceRecorder?.recordGitWorkingDirectoryPerformanceSnapshot(snapshot)
    }

    private func recordExactCleanContinuityState() {
        let acceptedCheckpointInstants = exactCleanAuthorityByWorktreeId.keys.compactMap {
            lastAcceptedStatusAtByWorktreeId[$0]
        }
        let oldestCheckpointAge =
            acceptedCheckpointInstants.min().map { acceptedAt in
                max(Duration.zero, deadlineClock.now - acceptedAt)
            } ?? .zero
        aggregatePerformance.recordExactCleanContinuityState(
            authorityCount: exactCleanAuthorityByWorktreeId.count,
            oldestCheckpointAgeMilliseconds: AgentStudioPerformanceTraceRecorder.milliseconds(
                from: oldestCheckpointAge
            )
        )
    }

    func demandClass(for worktreeId: UUID) -> String {
        explicitRefreshWorktreeIds.contains(worktreeId) ? "explicit" : demandTier(for: worktreeId).rawValue
    }

    func cadenceTier(for worktreeId: UUID) -> String {
        demandTier(for: worktreeId).rawValue
    }
}
