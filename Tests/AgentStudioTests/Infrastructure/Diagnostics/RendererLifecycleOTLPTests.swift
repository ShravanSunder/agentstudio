import Foundation
import Testing

@testable import AgentStudioInfrastructure

@Suite("Renderer lifecycle OTLP")
struct RendererLifecycleOTLPTests {
    @Test("startup diagnostic exports only bounded renderer lifecycle phases")
    func startupDiagnosticExportsBoundedRendererLifecyclePhase() {
        func projectedPhase(_ phase: String) -> AgentStudioTraceValue? {
            let record = AgentStudioTraceRecord(
                timeUnixNano: 88,
                severityText: .info,
                body: "app.startup_diagnostic_action.completed",
                traceID: nil,
                spanID: nil,
                parentSpanID: nil,
                resource: ["service.name": "AgentStudio"],
                scope: .init(name: "agentstudio.startup", version: "0.1.0"),
                attributes: [
                    "agentstudio.startup_diagnostic.renderer_lifecycle.phase": .string(phase)
                ]
            )
            return AgentStudioOTLPTraceProjection.project(record).attributes[
                "agentstudio.startup_diagnostic.renderer_lifecycle.phase"
            ]
        }

        #expect(projectedPhase("initial") == .string("initial"))
        #expect(projectedPhase("restart") == .string("restart"))
        #expect(projectedPhase("soak") == .string("soak"))
        #expect(projectedPhase("/private/unbounded-phase") == nil)
    }

    @Test("projection exports bounded aggregates and drops exact identity")
    func projectionScrubsExactIdentity() {
        let surfaceID = UUIDv7.generate().uuidString
        let record = AgentStudioTraceRecord(
            timeUnixNano: 89,
            severityText: .info,
            body: "performance.renderer.lifecycle",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.renderer.event.kind": .string("projection_evaluation"),
                "agentstudio.performance.renderer.projection.trigger": .string("observed_change"),
                "agentstudio.performance.renderer.projection.evaluation.delta": .int(1),
                "agentstudio.performance.renderer.projection.changed_surface.delta": .int(2),
                "agentstudio.performance.renderer.active.current": .int(3),
                "agentstudio.performance.renderer.orphan_candidate.current": .int(0),
                "agentstudio.performance.renderer.lifecycle.valid": .bool(true),
                "agentstudio.performance.renderer.surface_id": .string(surfaceID),
                "agentstudio.performance.renderer.raw_path": .string("/private/renderer-path"),
                "agentstudio.performance.renderer.title": .string("secret-title"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)
        let renderedProjection = projection.renderedForCanaryAssertions()

        #expect(
            projection.attributes["agentstudio.performance.renderer.event.kind"]
                == .string("projection_evaluation")
        )
        #expect(
            projection.attributes["agentstudio.performance.renderer.projection.trigger"]
                == .string("observed_change")
        )
        #expect(
            projection.attributes["agentstudio.performance.renderer.projection.evaluation.delta"] == .int(1)
        )
        #expect(projection.attributes["agentstudio.performance.renderer.lifecycle.valid"] == .bool(true))
        #expect(!renderedProjection.contains(surfaceID))
        #expect(!renderedProjection.contains("/private/renderer-path"))
        #expect(!renderedProjection.contains("secret-title"))
    }

    @Test("metric mapping uses counters for deltas and gauges for current values")
    func metricMappingUsesDeltasAndGauges() throws {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 119,
            severityText: .info,
            body: "performance.renderer.lifecycle",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.renderer.event.kind": .string("projection_evaluation"),
                "agentstudio.performance.renderer.projection.trigger": .string("membership_change"),
                "agentstudio.performance.renderer.projection.evaluation.delta": .int(1),
                "agentstudio.performance.renderer.projection.evaluation.total": .int(4),
                "agentstudio.performance.renderer.projection.changed_surface.delta": .int(2),
                "agentstudio.performance.renderer.active.current": .int(3),
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))
        let counterLabels = metricEvent.measurements.compactMap { measurement -> String? in
            guard case .counter(let sample) = measurement else { return nil }
            return sample.label
        }
        let gaugeLabels = metricEvent.measurements.compactMap { measurement -> String? in
            guard case .gauge(let sample) = measurement else { return nil }
            return sample.label
        }
        let projectionDelta = try #require(
            metricEvent.measurements.compactMap { measurement -> AgentStudioOTLPPerformanceMetricSample? in
                guard case .counter(let sample) = measurement,
                    sample.label == "agentstudio_performance_renderer_projection_evaluation_delta"
                else { return nil }
                return sample
            }.first
        )
        let activeGauge = try #require(
            metricEvent.measurements.compactMap { measurement -> AgentStudioOTLPPerformanceMetricSample? in
                guard case .gauge(let sample) = measurement,
                    sample.label == "agentstudio_performance_renderer_active_current"
                else { return nil }
                return sample
            }.first
        )

        #expect(
            metricEvent.dimensions == [
                .init(name: "event", value: "performance.renderer.lifecycle"),
                .init(name: "event_kind", value: "projection_evaluation"),
                .init(name: "projection_trigger", value: "membership_change"),
            ]
        )
        #expect(counterLabels.contains("agentstudio_performance_renderer_projection_evaluation_delta"))
        #expect(counterLabels.contains("agentstudio_performance_renderer_projection_changed_surface_delta"))
        #expect(gaugeLabels.contains("agentstudio_performance_renderer_projection_evaluation_total"))
        #expect(gaugeLabels.contains("agentstudio_performance_renderer_active_current"))
        #expect(projectionDelta.dimensions.map(\.name) == ["event", "event_kind", "projection_trigger"])
        #expect(activeGauge.dimensions.map(\.name) == ["event"])
    }
}
