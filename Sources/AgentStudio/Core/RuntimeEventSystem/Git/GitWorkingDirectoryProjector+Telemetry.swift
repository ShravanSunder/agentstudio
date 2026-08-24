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
        guard let performanceTraceRecorder else { return }
        for worktreeId in worktreeIds {
            performanceTraceRecorder.record(
                .gitAdmission,
                attributes: [
                    "agentstudio.worktree.id": .string(worktreeId.uuidString),
                    "agentstudio.performance.git.visibility_admission.outcome": .string(outcome.rawValue),
                    "agentstudio.performance.git.trigger_source": .string(
                        GitRefreshTriggerSource.visibilityChange.rawValue
                    ),
                    "agentstudio.performance.git.cadence_tier": .string(GitDemandTier.visibleSidebar.rawValue),
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
                    "agentstudio.performance.git.demand_class": .string(
                        refreshAttribution.admittedDemandClassByWorktreeId[worktreeId] ?? "background"
                    ),
                    "agentstudio.performance.git.trigger_source": .string(
                        (refreshAttribution.admittedTriggerSourceByWorktreeId[worktreeId] ?? .registration).rawValue
                    ),
                    "agentstudio.performance.git.cadence_tier": .string(
                        refreshAttribution.admittedCadenceTierByWorktreeId[worktreeId] ?? "1"
                    ),
                    "agentstudio.performance.git.request.sequence": .int(
                        Int(refreshAttribution.requestSequenceByWorktreeId[worktreeId] ?? 0)
                    ),
                ]
            )
        }
    }

    func demandClass(for worktreeId: UUID) -> String {
        explicitRefreshWorktreeIds.contains(worktreeId) ? "explicit" : demandTier(for: worktreeId).rawValue
    }

    func cadenceTier(for worktreeId: UUID) -> String {
        demandTier(for: worktreeId).rawValue
    }
}
