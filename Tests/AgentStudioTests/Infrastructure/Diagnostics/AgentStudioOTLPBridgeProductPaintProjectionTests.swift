import Testing

@testable import AgentStudio

extension AgentStudioOTLPBridgeTraceProjectionTests {
    @Test
    func bridgeProjectionPreservesOnlyScrubSafeProductPaintCorrelationFacts() {
        let prefix = "agentstudio.startup_diagnostic.bridge.product_paint"
        let projection = AgentStudioOTLPTraceProjection.project(
            AgentStudioTraceRecord(
                timeUnixNano: 134,
                severityText: .info,
                body: "app.startup_diagnostic_action.completed",
                traceID: nil,
                spanID: nil,
                parentSpanID: nil,
                resource: ["service.name": "AgentStudio"],
                scope: .init(name: "agentstudio.app.startup", version: "0.1.0"),
                attributes: [
                    "\(prefix).document_visible": .bool(true),
                    "\(prefix).file_mode_activated": .bool(true),
                    "\(prefix).file_selected_identity_matched": .bool(true),
                    "\(prefix).file_source_matched": .bool(true),
                    "\(prefix).file_source_match.count": .int(1),
                    "\(prefix).frame_live": .bool(true),
                    "\(prefix).review_selected_identity_matched": .bool(true),
                    "\(prefix).review_source_matched": .bool(true),
                    "\(prefix).review_source_match.count": .int(1),
                    "\(prefix).raw_path": .string("/Users/example/private/tracked.txt"),
                    "\(prefix).raw_sha256": .string("private-source-hash"),
                    "agentstudio.startup_diagnostic.render_proof.succeeded": .bool(true),
                ]
            )
        )

        #expect(projection.attributes["\(prefix).document_visible"] == .bool(true))
        #expect(projection.attributes["\(prefix).file_mode_activated"] == .bool(true))
        #expect(projection.attributes["\(prefix).file_selected_identity_matched"] == .bool(true))
        #expect(projection.attributes["\(prefix).file_source_matched"] == .bool(true))
        #expect(projection.attributes["\(prefix).file_source_match.count"] == .int(1))
        #expect(projection.attributes["\(prefix).frame_live"] == .bool(true))
        #expect(projection.attributes["\(prefix).review_selected_identity_matched"] == .bool(true))
        #expect(projection.attributes["\(prefix).review_source_matched"] == .bool(true))
        #expect(projection.attributes["\(prefix).review_source_match.count"] == .int(1))
        #expect(projection.attributes["\(prefix).raw_path"] == nil)
        #expect(projection.attributes["\(prefix).raw_sha256"] == nil)
    }
}
