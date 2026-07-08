import Foundation
import Testing

@testable import AgentStudio

@Suite
struct AgentStudioOTLPBridgeTelemetryProjectionTests {
    @Test
    func bridgeProjectionPreservesPackageBuildReason() {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 515,
            severityText: .info,
            body: "performance.bridge.swift.package_build",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: [
                "service.name": "AgentStudio"
            ],
            scope: .init(name: "agentstudio.bridge.performance.swift", version: "0.1.0"),
            attributes: [
                "agentstudio.bridge.package_build.reason": .string("initial_intake"),
                "agentstudio.bridge.phase": .string("package_build"),
                "agentstudio.bridge.plane": .string("data"),
                "agentstudio.bridge.priority": .string("cold"),
                "agentstudio.bridge.slice": .string("review_metadata"),
                "agentstudio.bridge.transport": .string("swift"),
                "agentstudio.trace.tag": .string("bridge.performance.swift"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)

        #expect(
            projection.attributes["agentstudio.bridge.package_build.reason"]
                == .string("initial_intake")
        )
    }

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

    @Test
    func bridgeProjectionPreservesFrameJankDiagnostics() {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 517,
            severityText: .info,
            body: "performance.bridge.web.frame_jank",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: [
                "service.name": "AgentStudio"
            ],
            scope: .init(name: "agentstudio.bridge.performance.web", version: "0.1.0"),
            attributes: [
                "agentstudio.bridge.frame_jank.dropped_frame.count": .int(3),
                "agentstudio.bridge.frame_jank.dropped_frame.worst_gap_ms": .double(72),
                "agentstudio.bridge.frame_jank.kind": .string("dropped_frame"),
                "agentstudio.bridge.frame_jank.long_task.count": .int(2),
                "agentstudio.bridge.frame_jank.long_task.max_ms": .double(54),
                "agentstudio.bridge.frame_jank.long_task.total_ms": .double(94),
                "agentstudio.bridge.phase": .string("frame_jank"),
                "agentstudio.bridge.plane": .string("control"),
                "agentstudio.bridge.priority": .string("hot"),
                "agentstudio.bridge.result": .string("success"),
                "agentstudio.bridge.slice": .string("frame_jank"),
                "agentstudio.bridge.transport": .string("local"),
                "agentstudio.bridge.viewer": .string("review"),
                "agentstudio.bridge.viewer.active": .bool(false),
                "agentstudio.trace.tag": .string("bridge.performance.web"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)

        #expect(
            projection.attributes["agentstudio.bridge.frame_jank.kind"]
                == .string("dropped_frame")
        )
        #expect(
            projection.attributes["agentstudio.bridge.frame_jank.dropped_frame.count"]
                == .int(3)
        )
        #expect(
            projection.attributes["agentstudio.bridge.frame_jank.dropped_frame.worst_gap_ms"]
                == .double(72)
        )
        #expect(
            projection.attributes["agentstudio.bridge.frame_jank.long_task.count"]
                == .int(2)
        )
        #expect(
            projection.attributes["agentstudio.bridge.frame_jank.long_task.max_ms"]
                == .double(54)
        )
        #expect(
            projection.attributes["agentstudio.bridge.frame_jank.long_task.total_ms"]
                == .double(94)
        )
        #expect(projection.attributes["agentstudio.bridge.viewer.active"] == .bool(false))
    }

    @Test
    func bridgeProjectionPreservesCommWorkerTaskTelemetryKeys() {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 516,
            severityText: .info,
            body: "performance.bridge.worker.task",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: [
                "service.name": "AgentStudio"
            ],
            scope: .init(name: "agentstudio.bridge.performance.web", version: "0.1.0"),
            attributes: [
                "agentstudio.bridge.phase": .string("worker_task"),
                "agentstudio.bridge.plane": .string("data"),
                "agentstudio.bridge.priority": .string("hot"),
                "agentstudio.bridge.result": .string("success"),
                "agentstudio.bridge.slice": .string("worker_task"),
                "agentstudio.bridge.transport": .string("worker"),
                "agentstudio.bridge.worker.action": .string("applySelectedFact"),
                "agentstudio.bridge.worker.command": .string("select"),
                "agentstudio.bridge.worker.handler_duration_ms": .double(2.5),
                "agentstudio.bridge.worker.lane": .string("selected"),
                "agentstudio.bridge.worker.patch_count": .int(2),
                "agentstudio.bridge.worker.payload_class": .string("inline"),
                "agentstudio.bridge.worker.queue_wait_ms": .double(4.25),
                "agentstudio.bridge.worker.source_epoch": .int(7),
                "agentstudio.bridge.worker.task_kind": .string("store_action"),
                "agentstudio.bridge.worker.touched_key_count": .int(5),
                "agentstudio.bridge.worker.work_kind": .string("review_content_ready"),
                "agentstudio.trace.tag": .string("bridge.performance.web"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)

        #expect(projection.attributes["agentstudio.bridge.worker.action"] == .string("applySelectedFact"))
        #expect(projection.attributes["agentstudio.bridge.worker.command"] == .string("select"))
        #expect(projection.attributes["agentstudio.bridge.worker.handler_duration_ms"] == .double(2.5))
        #expect(projection.attributes["agentstudio.bridge.worker.lane"] == .string("selected"))
        #expect(projection.attributes["agentstudio.bridge.worker.patch_count"] == .int(2))
        #expect(projection.attributes["agentstudio.bridge.worker.payload_class"] == .string("inline"))
        #expect(projection.attributes["agentstudio.bridge.worker.queue_wait_ms"] == .double(4.25))
        #expect(projection.attributes["agentstudio.bridge.worker.source_epoch"] == .int(7))
        #expect(projection.attributes["agentstudio.bridge.worker.task_kind"] == .string("store_action"))
        #expect(projection.attributes["agentstudio.bridge.worker.touched_key_count"] == .int(5))
        #expect(projection.attributes["agentstudio.bridge.worker.work_kind"] == .string("review_content_ready"))
    }
}
