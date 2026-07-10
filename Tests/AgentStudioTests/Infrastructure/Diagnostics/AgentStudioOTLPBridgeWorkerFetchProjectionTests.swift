import Foundation
import Testing

@testable import AgentStudio

extension AgentStudioOTLPBridgeTraceProjectionTests {
    @Test
    func bridgeProjectionPreservesSafeWorkerFetchStartupDiagnostics() {
        let projection = AgentStudioOTLPTraceProjection.project(
            makeWorkerFetchStartupDiagnosticProjectionCanaryRecord()
        )
        let renderedAttributes = projection.attributes.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        #expect(
            projection.attributes["agentstudio.startup_diagnostic.bridge.worker_fetch.marker.count"] == .int(1))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.worker_fetch.worker_observed_byte.count"
            ] == .int(21))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.worker_fetch.stream_first_chunk_byte.count"
            ] == .int(21))
        #expect(
            projection.attributes["agentstudio.startup_diagnostic.bridge.worker_fetch.stream_held_open"] == .bool(true))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.worker_fetch.worker_script_fetch.succeeded"
            ] == .bool(true))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.worker_fetch.worker_script_fetch.status"
            ] == .int(200))
        #expect(
            projection.attributes["agentstudio.startup_diagnostic.bridge.worker_fetch.content_url.scheme"]
                == .string("agentstudio"))
        #expect(
            projection.attributes["agentstudio.startup_diagnostic.bridge.worker_fetch.bootstrap.mode"]
                == .string("blob_classic"))
        #expect(
            projection.attributes["agentstudio.startup_diagnostic.bridge.worker_fetch.raw_url"] == nil)
        #expect(
            projection.attributes["agentstudio.startup_diagnostic.bridge.worker_fetch.raw_path"] == nil)
        #expect(!renderedAttributes.contains("agentstudio://resource/review/content/private"))
        #expect(!renderedAttributes.contains("/Users/example/project/private.swift"))
    }

    @Test
    func bridgeProjectionPreservesSafeProductStreamWebKitFeasibilityFacts() {
        let projection = AgentStudioOTLPTraceProjection.project(
            makeProductStreamWebKitFeasibilityProjectionCanaryRecord()
        )

        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.product_stream_webkit.carrier.succeeded"
            ] == .bool(true))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.product_stream_webkit.authentication_before_body.succeeded"
            ] == .bool(true))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.product_stream_webkit.total_body_read.count"
            ] == .int(11))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.product_stream_webkit.frame_receipt.count"
            ] == .int(4))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.product_stream_webkit.abort_causal_cancellation.succeeded"
            ] == .bool(true))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.product_stream_webkit.valid_stream_ended"
            ] == .bool(true))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.product_stream_webkit.worker_observed_exact_frames"
            ] == .bool(true))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.product_stream_webkit.active_producer_task.count"
            ] == .int(0))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.product_stream_webkit.post_terminal_frame.count"
            ] == .int(0))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.product_stream_webkit.failure.reason"
            ] == .string("none"))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.product_stream_webkit.raw_capability"
            ] == nil)
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.product_stream_webkit.raw_body"
            ] == nil)
    }
}

private func makeWorkerFetchStartupDiagnosticProjectionCanaryRecord() -> AgentStudioTraceRecord {
    AgentStudioTraceRecord(
        timeUnixNano: 132,
        severityText: .info,
        body: "app.startup_diagnostic_action.completed",
        traceID: nil,
        spanID: nil,
        parentSpanID: nil,
        resource: [
            "service.name": "AgentStudio"
        ],
        scope: .init(name: "agentstudio.app.startup", version: "0.1.0"),
        attributes: [
            "agentstudio.startup_diagnostic.action": .string("bridge-worker-fetch-scheme-smoke"),
            "agentstudio.startup_diagnostic.bridge.worker_fetch.marker.count": .int(1),
            "agentstudio.startup_diagnostic.bridge.worker_fetch.content_url.scheme": .string("agentstudio"),
            "agentstudio.startup_diagnostic.bridge.worker_fetch.content_resource.kind": .string("content"),
            "agentstudio.startup_diagnostic.bridge.worker_fetch.bootstrap.mode": .string("blob_classic"),
            "agentstudio.startup_diagnostic.bridge.worker_fetch.worker_observed_byte.count": .int(21),
            "agentstudio.startup_diagnostic.bridge.worker_fetch.stream_first_chunk_byte.count": .int(21),
            "agentstudio.startup_diagnostic.bridge.worker_fetch.stream_held_open": .bool(true),
            "agentstudio.startup_diagnostic.bridge.worker_fetch.worker_script_fetch.succeeded": .bool(true),
            "agentstudio.startup_diagnostic.bridge.worker_fetch.worker_script_fetch.status": .int(200),
            "agentstudio.startup_diagnostic.bridge.worker_fetch.raw_url": .string(
                "agentstudio://resource/review/content/private?generation=7"),
            "agentstudio.startup_diagnostic.bridge.worker_fetch.raw_path": .string(
                "/Users/example/project/private.swift"),
            "agentstudio.startup_diagnostic.render_proof.succeeded": .bool(true),
        ]
    )
}

private func makeProductStreamWebKitFeasibilityProjectionCanaryRecord() -> AgentStudioTraceRecord {
    AgentStudioTraceRecord(
        timeUnixNano: 133,
        severityText: .info,
        body: "app.startup_diagnostic_action.completed",
        traceID: nil,
        spanID: nil,
        parentSpanID: nil,
        resource: [
            "service.name": "AgentStudio"
        ],
        scope: .init(name: "agentstudio.app.startup", version: "0.1.0"),
        attributes: [
            "agentstudio.startup_diagnostic.action": .string(
                "bridge-product-stream-webkit-feasibility"),
            "agentstudio.startup_diagnostic.bridge.product_stream_webkit.carrier.succeeded":
                .bool(true),
            "agentstudio.startup_diagnostic.bridge.product_stream_webkit.authentication_before_body.succeeded":
                .bool(true),
            "agentstudio.startup_diagnostic.bridge.product_stream_webkit.total_body_read.count": .int(11),
            "agentstudio.startup_diagnostic.bridge.product_stream_webkit.frame_receipt.count": .int(4),
            "agentstudio.startup_diagnostic.bridge.product_stream_webkit.abort_causal_cancellation.succeeded":
                .bool(true),
            "agentstudio.startup_diagnostic.bridge.product_stream_webkit.valid_stream_ended":
                .bool(true),
            "agentstudio.startup_diagnostic.bridge.product_stream_webkit.worker_observed_exact_frames":
                .bool(true),
            "agentstudio.startup_diagnostic.bridge.product_stream_webkit.active_producer_task.count":
                .int(0),
            "agentstudio.startup_diagnostic.bridge.product_stream_webkit.post_terminal_frame.count":
                .int(0),
            "agentstudio.startup_diagnostic.bridge.product_stream_webkit.failure.reason":
                .string("none"),
            "agentstudio.startup_diagnostic.bridge.product_stream_webkit.raw_capability":
                .string("private-capability"),
            "agentstudio.startup_diagnostic.bridge.product_stream_webkit.raw_body":
                .string("private-body"),
        ]
    )
}
