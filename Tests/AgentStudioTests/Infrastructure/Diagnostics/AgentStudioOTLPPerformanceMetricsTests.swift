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
            parentSpanID: nil,
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
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.persistence", version: "0.1.0"),
            attributes: [
                "agentstudio.persistence.operation": .string("workspace.load")
            ]
        )

        #expect(AgentStudioOTLPPerformanceMetricEvent(record: record) == nil)
    }

    @Test
    func bridgePerformanceRecordProjectsOnlySafeBridgeMetrics() throws {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 124,
            severityText: .info,
            body: "performance.bridge.webkit.package_push",
            traceID: "11111111111111111111111111111111",
            spanID: "2222222222222222",
            parentSpanID: "3333333333333333",
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.bridge.performance.webkit", version: "0.1.0"),
            attributes: [
                "agentstudio.bridge.content.byte_size_bucket": .int(100_000),
                "agentstudio.bridge.content.line_count_bucket": .int(500),
                "agentstudio.bridge.item_id": .string("private-item-id"),
                "agentstudio.bridge.phase": .string("package_push"),
                "agentstudio.performance.elapsed_ms": .double(8.5),
                "agentstudio.trace.tag": .string("bridge.performance.webkit"),
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))

        #expect(metricEvent.eventName == "performance.bridge.webkit.package_push")
        #expect(metricEvent.elapsedMilliseconds == 8.5)
        #expect(
            metricEvent.samples == [
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.bridge.webkit.package_push",
                    label: "agentstudio_bridge_content_byte_size_bucket",
                    value: 100_000
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.bridge.webkit.package_push",
                    label: "agentstudio_bridge_content_line_count_bucket",
                    value: 500
                ),
            ])
    }
}
