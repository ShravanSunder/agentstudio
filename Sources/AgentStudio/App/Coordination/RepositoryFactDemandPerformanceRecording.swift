import AgentStudioInfrastructure

struct RepositoryFactDemandPerformanceSnapshot: Equatable, Sendable {
    var projected: UInt64 = 0
    var contentEqual: UInt64 = 0
    var delivered: UInt64 = 0
    var cleared: UInt64 = 0
    var rejectedAfterShutdown: UInt64 = 0

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
            ]
        )
    }

    private static func repositoryDemandTraceInteger(_ value: UInt64) -> AgentStudioTraceValue {
        .int(value > UInt64(Int.max) ? Int.max : Int(value))
    }
}
