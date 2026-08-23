import Foundation
import Testing

@testable import AgentStudioInfrastructure

@Suite
struct BridgeRenderDispositionOTLPMetricsTests {
    @Test
    func admissionProjectsBoundedDimensionsAndMeasurements() throws {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 123,
            severityText: .info,
            body: "performance.bridge.web.render_disposition_admission",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.bridge.performance.web", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.elapsed_ms": .double(4.5),
                "agentstudio.bridge.phase": .string("render_disposition_batch_terminal"),
                "agentstudio.bridge.plane": .string("control"),
                "agentstudio.bridge.priority": .string("warm"),
                "agentstudio.bridge.render_disposition.batch_receipt_count": .int(64),
                "agentstudio.bridge.render_disposition.duplicate_count": .int(1),
                "agentstudio.bridge.render_disposition.oldest_pending_age_ms": .double(2),
                "agentstudio.bridge.render_disposition.outcome": .string("acked"),
                "agentstudio.bridge.render_disposition.pending_count": .int(3),
                "agentstudio.bridge.render_disposition.pending_high_water_mark": .int(65),
                "agentstudio.bridge.render_disposition.produced_count": .int(66),
                "agentstudio.bridge.slice": .string("command_acks"),
                "agentstudio.bridge.viewer": .string("review"),
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))

        #expect(metricEvent.elapsedMilliseconds == 4.5)
        #expect(metricEvent.dimensions.contains(.init(name: "viewer", value: "review")))
        #expect(metricEvent.dimensions.contains(.init(name: "render_disposition_outcome", value: "acked")))
        #expect(
            metricEvent.samples.map(\.label) == [
                "agentstudio_bridge_render_disposition_batch_receipt_count",
                "agentstudio_bridge_render_disposition_duplicate_count",
                "agentstudio_bridge_render_disposition_oldest_pending_age_ms",
                "agentstudio_bridge_render_disposition_pending_count",
                "agentstudio_bridge_render_disposition_pending_high_water_mark",
                "agentstudio_bridge_render_disposition_produced_count",
            ]
        )
    }
}
