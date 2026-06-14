import Testing

@testable import AgentStudio

@Suite
struct AgentStudioOTLPPerformanceMetricsTests {
    @Test
    func performanceRecordProjectsBoundedMetricsFromScrubbedAttributes() throws {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 123,
            severityText: .info,
            body: "performance.git.status",
            traceID: nil,
            spanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.elapsed_ms": .double(15.5),
                "agentstudio.performance.git.pending.count": .int(64),
                "agentstudio.performance.git.running.count": .int(4),
                "agentstudio.performance.git.has_git_internal_changes": .bool(true),
                "agentstudio.performance.git.root_path": .string("/Users/private/repo"),
                "agentstudio.trace.tag": .string("performance"),
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))

        #expect(metricEvent.eventName == "performance.git.status")
        #expect(metricEvent.elapsedMilliseconds == 15.5)
        #expect(
            metricEvent.samples == [
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.git.status",
                    label: "agentstudio_performance_git_has_git_internal_changes",
                    value: 1
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.git.status",
                    label: "agentstudio_performance_git_pending_count",
                    value: 64
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.git.status",
                    label: "agentstudio_performance_git_running_count",
                    value: 4
                ),
            ])
    }

    @Test
    func nonPerformanceRecordsDoNotProducePerformanceMetrics() {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 123,
            severityText: .info,
            body: "persistence.operation.phase",
            traceID: nil,
            spanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.persistence", version: "0.1.0"),
            attributes: [
                "agentstudio.persistence.operation": .string("workspace.load")
            ]
        )

        #expect(AgentStudioOTLPPerformanceMetricEvent(record: record) == nil)
    }
}
