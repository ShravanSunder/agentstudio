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
            projection.attributes["agentstudio.startup_diagnostic.bridge.worker_fetch.raw_url"] == nil)
        #expect(
            projection.attributes["agentstudio.startup_diagnostic.bridge.worker_fetch.raw_path"] == nil)
        #expect(!renderedAttributes.contains("agentstudio://resource/review/content/private"))
        #expect(!renderedAttributes.contains("/Users/example/project/private.swift"))
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
