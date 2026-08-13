import AgentStudioInfrastructure
import Foundation

/// Trace-attribute assembly for git status computes, split from the actor
/// body to stay under the type-length cap.
extension GitWorkingDirectoryProjector {
    func gitStatusTraceAttributes(
        for changeset: FileChangeset,
        unavailable: GitWorkingTreeStatusUnavailable?,
        scope: GitStatusScope = .full,
        pathspecCount: Int = 0
    ) -> [String: AgentStudioTraceValue] {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.worktree.id": .string(changeset.worktreeId.uuidString),
            "agentstudio.performance.git.input_path.count": .int(changeset.paths.count),
            "agentstudio.performance.git.pending.count": .int(pendingByWorktreeId.count),
            "agentstudio.performance.git.running.count": .int(worktreeTasks.count),
            "agentstudio.performance.git.has_git_internal_changes": .bool(changeset.containsGitInternalChanges),
            "agentstudio.performance.git.suppressed_ignored_path.count": .int(changeset.suppressedIgnoredPathCount),
            "agentstudio.performance.git.suppressed_git_internal_path.count": .int(
                changeset.suppressedGitInternalPathCount
            ),
            "agentstudio.performance.git.status_scope": .string(scope.traceValue),
            "agentstudio.performance.git.pathspec.count": .int(pathspecCount),
            "agentstudio.performance.git.demand_class": .string(
                refreshAttribution.admittedDemandClassByWorktreeId[changeset.worktreeId] ?? "background"
            ),
            "agentstudio.performance.git.trigger_source": .string(
                (refreshAttribution.admittedTriggerSourceByWorktreeId[changeset.worktreeId] ?? .registration).rawValue
            ),
            "agentstudio.performance.git.cadence_tier": .string(
                refreshAttribution.admittedCadenceTierByWorktreeId[changeset.worktreeId] ?? "1"
            ),
            "agentstudio.performance.git.request.sequence": .int(
                Int(refreshAttribution.requestSequenceByWorktreeId[changeset.worktreeId] ?? 0)
            ),
        ]
        if let unavailable {
            attributes["agentstudio.performance.git.status_unavailable.reason"] = .string(unavailable.reason.rawValue)
        }
        return attributes
    }
}
