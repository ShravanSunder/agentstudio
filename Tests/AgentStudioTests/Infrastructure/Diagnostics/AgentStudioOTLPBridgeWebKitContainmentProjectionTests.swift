import Foundation
import Testing

@testable import AgentStudio

@Suite
struct AgentStudioOTLPWebKitContainmentTests {
    @Test
    func webKitProductSchemeFailureContainmentPreservesOnlySafeDiagnostics() {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 515,
            severityText: .info,
            body: "performance.bridge.webkit.product_scheme_failure_contained",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: [
                "service.name": "AgentStudio"
            ],
            scope: .init(name: BridgeTelemetryScope.webKit.traceTag.rawValue, version: "0.1.0"),
            attributes: [
                "agentstudio.bridge.phase": .string("error"),
                "agentstudio.bridge.plane": .string("observability"),
                "agentstudio.bridge.priority": .string("hot"),
                "agentstudio.bridge.result": .string("failure"),
                "agentstudio.bridge.result_reason": .string("frame_delivery_rejected"),
                "agentstudio.bridge.slice": .string("connection_health"),
                "agentstudio.bridge.transport": .string("scheme"),
                "agentstudio.bridge.raw_error": .string("private WebKit error"),
                "agentstudio.bridge.raw_path": .string("/Users/private/repo/Sources/App.swift"),
                "agentstudio.bridge.request_id": .string("private-request-id"),
                "agentstudio.bridge.raw_payload": .string("private source payload"),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)
        let renderedProjection = renderedProjectionForCanaryAssertions(projection)

        #expect(projection.body == "performance.bridge.webkit.product_scheme_failure_contained")
        #expect(projection.attributes["agentstudio.bridge.phase"] == .string("error"))
        #expect(projection.attributes["agentstudio.bridge.plane"] == .string("observability"))
        #expect(projection.attributes["agentstudio.bridge.priority"] == .string("hot"))
        #expect(projection.attributes["agentstudio.bridge.result"] == .string("failure"))
        #expect(
            projection.attributes["agentstudio.bridge.result_reason"] == .string("frame_delivery_rejected")
        )
        #expect(projection.attributes["agentstudio.bridge.slice"] == .string("connection_health"))
        #expect(projection.attributes["agentstudio.bridge.transport"] == .string("scheme"))
        #expect(projection.attributes["agentstudio.bridge.raw_error"] == nil)
        #expect(projection.attributes["agentstudio.bridge.raw_path"] == nil)
        #expect(projection.attributes["agentstudio.bridge.request_id"] == nil)
        #expect(projection.attributes["agentstudio.bridge.raw_payload"] == nil)
        #expect(!renderedProjection.contains("private WebKit error"))
        #expect(!renderedProjection.contains("/Users/private/repo/Sources/App.swift"))
        #expect(!renderedProjection.contains("private-request-id"))
        #expect(!renderedProjection.contains("private source payload"))
    }

    private func renderedProjectionForCanaryAssertions(
        _ projection: AgentStudioOTLPProjectedLogRecord
    ) -> String {
        [
            projection.body,
            projection.resource.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "),
            projection.attributes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "),
        ].joined(separator: "\n")
    }
}
