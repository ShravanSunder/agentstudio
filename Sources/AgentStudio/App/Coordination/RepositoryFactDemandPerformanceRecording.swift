import AgentStudioInfrastructure

struct RepositoryFactDemandPerformanceSnapshot: Equatable, Sendable {
    var projected: UInt64 = 0
    var contentEqual: UInt64 = 0
    var delivered: UInt64 = 0
    var cleared: UInt64 = 0
    var rejectedAfterShutdown: UInt64 = 0
    var boundaryReclassified: UInt64 = 0
    var recencyReactivated: UInt64 = 0
    var paneReactivated: UInt64 = 0
    var hydrationUnclassifiedCurrent: UInt64 = 0
    var warmRepositoryCurrent: UInt64 = 0
    var unknownRepositoryCurrent: UInt64 = 0
    var inactiveRepositoryCurrent: UInt64 = 0
    var warmWorktreeCurrent: UInt64 = 0
    var unknownWorktreeCurrent: UInt64 = 0
    var unknownBackgroundOnlyCurrent: UInt64 = 0
    var unknownRemoteDemandCurrent: UInt64 = 0
    var unknownForgeDemandCurrent: UInt64 = 0
    var applied: UInt64 = 0
    var appliedUnknownWorktreeCurrent: UInt64 = 0
    var appliedUnknownBackgroundOnlyCurrent: UInt64 = 0
    var appliedUnknownRemoteDemandCurrent: UInt64 = 0
    var appliedUnknownForgeDemandCurrent: UInt64 = 0
    var inactiveWorktreeCurrent: UInt64 = 0
    var inactiveRemoteSuppressedCurrent: UInt64 = 0
    var inactiveForgeSuppressedCurrent: UInt64 = 0

    var inputCount: UInt64 { projected + rejectedAfterShutdown }
    var isEmpty: Bool { self == Self() }
}

protocol RepositoryFactDemandPerformanceRecording: Sendable {
    func recordRepositoryFactDemandPerformanceSnapshot(
        _ snapshot: RepositoryFactDemandPerformanceSnapshot
    )
}

extension AgentStudioPerformanceTraceRecorder: RepositoryFactDemandPerformanceRecording {
    func recordRepositoryFactDemandPerformanceSnapshot(
        _ snapshot: RepositoryFactDemandPerformanceSnapshot
    ) {
        guard !snapshot.isEmpty else { return }
        record(
            .repositoryFactDemand,
            attributes: [
                "agentstudio.performance.repository_fact_demand.projected.count": Self.repositoryDemandTraceInteger(
                    snapshot.projected),
                "agentstudio.performance.repository_fact_demand.content_equal.count": Self.repositoryDemandTraceInteger(
                    snapshot.contentEqual),
                "agentstudio.performance.repository_fact_demand.delivered.count": Self.repositoryDemandTraceInteger(
                    snapshot.delivered),
                "agentstudio.performance.repository_fact_demand.cleared.count": Self.repositoryDemandTraceInteger(
                    snapshot.cleared),
                "agentstudio.performance.repository_fact_demand.rejected_after_shutdown.count":
                    Self.repositoryDemandTraceInteger(
                        snapshot.rejectedAfterShutdown),
                "agentstudio.performance.repository_fact_demand.activity.boundary_reclassified.count":
                    Self.repositoryDemandTraceInteger(snapshot.boundaryReclassified),
                "agentstudio.performance.repository_fact_demand.activity.recency_reactivated.count":
                    Self.repositoryDemandTraceInteger(snapshot.recencyReactivated),
                "agentstudio.performance.repository_fact_demand.activity.pane_reactivated.count":
                    Self.repositoryDemandTraceInteger(snapshot.paneReactivated),
                "agentstudio.performance.repository_fact_demand.activity.hydration_unclassified.current":
                    Self.repositoryDemandTraceInteger(snapshot.hydrationUnclassifiedCurrent),
                "agentstudio.performance.repository_fact_demand.activity.warm_repository.current":
                    Self.repositoryDemandTraceInteger(snapshot.warmRepositoryCurrent),
                "agentstudio.performance.repository_fact_demand.activity.unknown_repository.current":
                    Self.repositoryDemandTraceInteger(snapshot.unknownRepositoryCurrent),
                "agentstudio.performance.repository_fact_demand.activity.inactive_repository.current":
                    Self.repositoryDemandTraceInteger(snapshot.inactiveRepositoryCurrent),
                "agentstudio.performance.repository_fact_demand.activity.warm_worktree.current":
                    Self.repositoryDemandTraceInteger(snapshot.warmWorktreeCurrent),
                "agentstudio.performance.repository_fact_demand.activity.unknown_worktree.current":
                    Self.repositoryDemandTraceInteger(snapshot.unknownWorktreeCurrent),
                "agentstudio.performance.repository_fact_demand.unknown.background_only.current":
                    Self.repositoryDemandTraceInteger(snapshot.unknownBackgroundOnlyCurrent),
                "agentstudio.performance.repository_fact_demand.unknown.remote_demand.current":
                    Self.repositoryDemandTraceInteger(snapshot.unknownRemoteDemandCurrent),
                "agentstudio.performance.repository_fact_demand.unknown.forge_demand.current":
                    Self.repositoryDemandTraceInteger(snapshot.unknownForgeDemandCurrent),
                "agentstudio.performance.repository_fact_demand.pipeline.applied.count":
                    Self.repositoryDemandTraceInteger(snapshot.applied),
                "agentstudio.performance.repository_fact_demand.pipeline.unknown_worktree.current":
                    Self.repositoryDemandTraceInteger(snapshot.appliedUnknownWorktreeCurrent),
                "agentstudio.performance.repository_fact_demand.pipeline.unknown_background_only.current":
                    Self.repositoryDemandTraceInteger(snapshot.appliedUnknownBackgroundOnlyCurrent),
                "agentstudio.performance.repository_fact_demand.pipeline.unknown_remote_demand.current":
                    Self.repositoryDemandTraceInteger(snapshot.appliedUnknownRemoteDemandCurrent),
                "agentstudio.performance.repository_fact_demand.pipeline.unknown_forge_demand.current":
                    Self.repositoryDemandTraceInteger(snapshot.appliedUnknownForgeDemandCurrent),
                "agentstudio.performance.repository_fact_demand.activity.inactive_worktree.current":
                    Self.repositoryDemandTraceInteger(snapshot.inactiveWorktreeCurrent),
                "agentstudio.performance.repository_fact_demand.inactive.remote_suppressed.current":
                    Self.repositoryDemandTraceInteger(snapshot.inactiveRemoteSuppressedCurrent),
                "agentstudio.performance.repository_fact_demand.inactive.forge_suppressed.current":
                    Self.repositoryDemandTraceInteger(snapshot.inactiveForgeSuppressedCurrent),
            ]
        )
    }

    private static func repositoryDemandTraceInteger(_ value: UInt64) -> AgentStudioTraceValue {
        .int(value > UInt64(Int.max) ? Int.max : Int(value))
    }
}
