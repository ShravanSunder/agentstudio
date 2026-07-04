import Foundation
import Testing

@testable import AgentStudio

@Suite
struct AgentStudioOTLPBridgeTelemetryProjectionTests {
    @Test
    func bridgeProjectionPreservesTelemetryDropAggregateCounterKeys() {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 514,
            severityText: .info,
            body: "performance.bridge.web.telemetry_drop",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: [
                "service.name": "AgentStudio"
            ],
            scope: .init(name: "agentstudio.bridge.performance.web", version: "0.1.0"),
            attributes: [
                "agentstudio.bridge.phase": .string("dropped"),
                "agentstudio.bridge.plane": .string("observability"),
                "agentstudio.bridge.priority": .string("best_effort"),
                "agentstudio.bridge.result": .string("dropped"),
                "agentstudio.bridge.slice": .string("telemetry_drop"),
                "agentstudio.bridge.telemetry.drop_reason": .string("encoded_byte_cap"),
                "agentstudio.bridge.telemetry.dropped_count": .int(2),
                "agentstudio.bridge.telemetry.event_name": .string("performance.bridge.web.first_render"),
                "agentstudio.bridge.telemetry.lane": .string("best_effort"),
                "agentstudio.bridge.telemetry.result": .string("success"),
                "agentstudio.bridge.transport": .string("scheme"),
                "agentstudio.trace.tag": .string("bridge.performance.web"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)

        #expect(
            projection.attributes["agentstudio.bridge.telemetry.event_name"]
                == .string("performance.bridge.web.first_render")
        )
        #expect(projection.attributes["agentstudio.bridge.telemetry.lane"] == .string("best_effort"))
        #expect(projection.attributes["agentstudio.bridge.telemetry.result"] == .string("success"))
    }
}
