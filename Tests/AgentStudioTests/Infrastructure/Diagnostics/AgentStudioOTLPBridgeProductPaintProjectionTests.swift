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
                    "\(prefix).file_identity_chain_matched": .bool(true),
                    "\(prefix).file_mode_activated": .bool(true),
                    "\(prefix).file_selected_identity_matched": .bool(true),
                    "\(prefix).file_source_matched": .bool(true),
                    "\(prefix).file_source_match.count": .int(1),
                    "\(prefix).frame_live": .bool(true),
                    "\(prefix).review_identity_chain_matched": .bool(true),
                    "\(prefix).review_selected_identity_matched": .bool(true),
                    "\(prefix).review_source_matched": .bool(true),
                    "\(prefix).review_source_match.count": .int(1),
                    "\(prefix).reload_replay_succeeded": .bool(true),
                    "\(prefix).worker_replacement_observed": .bool(true),
                    "\(prefix).raw_path": .string("/Users/example/private/tracked.txt"),
                    "\(prefix).raw_sha256": .string("private-source-hash"),
                    "\(prefix).raw_descriptor_id": .string("private-descriptor"),
                    "\(prefix).raw_request_id": .string("private-request"),
                    "\(prefix).raw_source_identity": .string("private-source"),
                    "\(prefix).raw_publication_id": .string("private-publication"),
                    "\(prefix).raw_item_id": .string("private-item"),
                    "\(prefix).raw_readable_text": .string("private-source-text"),
                    "agentstudio.startup_diagnostic.render_proof.succeeded": .bool(true),
                ]
            )
        )

        #expect(projection.attributes["\(prefix).document_visible"] == .bool(true))
        #expect(projection.attributes["\(prefix).file_identity_chain_matched"] == .bool(true))
        #expect(projection.attributes["\(prefix).file_mode_activated"] == .bool(true))
        #expect(projection.attributes["\(prefix).file_selected_identity_matched"] == .bool(true))
        #expect(projection.attributes["\(prefix).file_source_matched"] == .bool(true))
        #expect(projection.attributes["\(prefix).file_source_match.count"] == .int(1))
        #expect(projection.attributes["\(prefix).frame_live"] == .bool(true))
        #expect(projection.attributes["\(prefix).review_identity_chain_matched"] == .bool(true))
        #expect(projection.attributes["\(prefix).review_selected_identity_matched"] == .bool(true))
        #expect(projection.attributes["\(prefix).review_source_matched"] == .bool(true))
        #expect(projection.attributes["\(prefix).review_source_match.count"] == .int(1))
        #expect(projection.attributes["\(prefix).reload_replay_succeeded"] == .bool(true))
        #expect(projection.attributes["\(prefix).worker_replacement_observed"] == .bool(true))
        #expect(projection.attributes["\(prefix).raw_path"] == nil)
        #expect(projection.attributes["\(prefix).raw_sha256"] == nil)
        #expect(projection.attributes["\(prefix).raw_descriptor_id"] == nil)
        #expect(projection.attributes["\(prefix).raw_request_id"] == nil)
        #expect(projection.attributes["\(prefix).raw_source_identity"] == nil)
        #expect(projection.attributes["\(prefix).raw_publication_id"] == nil)
        #expect(projection.attributes["\(prefix).raw_item_id"] == nil)
        #expect(projection.attributes["\(prefix).raw_readable_text"] == nil)
    }
}
