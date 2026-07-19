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
                    "\(prefix).painted_element.count": .int(2),
                    "\(prefix).decoded_correlation.count": .int(3),
                    "\(prefix).review_candidate.surface_role.count": .int(2),
                    "\(prefix).review_candidate.identity.count": .int(2),
                    "\(prefix).review_candidate.selected_item.count": .int(1),
                    "\(prefix).review_candidate.whole_position.count": .int(2),
                    "\(prefix).review_candidate.digest.count": .int(1),
                    "\(prefix).review_candidate.painted_disposition.count": .int(2),
                    "\(prefix).review_candidate.canary.count": .int(1),
                    "\(prefix).active_mode_review": .bool(true),
                    "\(prefix).review_metadata_item.count": .int(257),
                    "\(prefix).review_selection.initial_requested.count": .int(1),
                    "\(prefix).review_selection.initial_scheduling_accepted.count": .int(2),
                    "\(prefix).review_selection.scheduled.count": .int(3),
                    "\(prefix).review_selection.first_frame_reached.count": .int(4),
                    "\(prefix).review_selection.second_frame_reached.count": .int(5),
                    "\(prefix).review_selection.submitted.count": .int(6),
                    "\(prefix).review_selection.dropped.count": .int(7),
                    "\(prefix).review_shell_present": .bool(true),
                    "\(prefix).review_selected_item_present": .bool(true),
                    "\(prefix).review_selected_path_present": .bool(true),
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
        assertReviewProductPaintStageProjection(projection, prefix: prefix)
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

    private func assertReviewProductPaintStageProjection(
        _ projection: AgentStudioOTLPProjectedLogRecord,
        prefix: String
    ) {
        #expect(projection.attributes["\(prefix).painted_element.count"] == .int(2))
        #expect(projection.attributes["\(prefix).decoded_correlation.count"] == .int(3))
        #expect(projection.attributes["\(prefix).review_candidate.surface_role.count"] == .int(2))
        #expect(projection.attributes["\(prefix).review_candidate.identity.count"] == .int(2))
        #expect(projection.attributes["\(prefix).review_candidate.selected_item.count"] == .int(1))
        #expect(projection.attributes["\(prefix).review_candidate.whole_position.count"] == .int(2))
        #expect(projection.attributes["\(prefix).review_candidate.digest.count"] == .int(1))
        #expect(projection.attributes["\(prefix).review_candidate.painted_disposition.count"] == .int(2))
        #expect(projection.attributes["\(prefix).review_candidate.canary.count"] == .int(1))
        #expect(projection.attributes["\(prefix).active_mode_review"] == .bool(true))
        #expect(projection.attributes["\(prefix).review_metadata_item.count"] == .int(257))
        #expect(projection.attributes["\(prefix).review_selection.initial_requested.count"] == .int(1))
        #expect(
            projection.attributes["\(prefix).review_selection.initial_scheduling_accepted.count"]
                == .int(2)
        )
        #expect(projection.attributes["\(prefix).review_selection.scheduled.count"] == .int(3))
        #expect(projection.attributes["\(prefix).review_selection.first_frame_reached.count"] == .int(4))
        #expect(projection.attributes["\(prefix).review_selection.second_frame_reached.count"] == .int(5))
        #expect(projection.attributes["\(prefix).review_selection.submitted.count"] == .int(6))
        #expect(projection.attributes["\(prefix).review_selection.dropped.count"] == .int(7))
        #expect(projection.attributes["\(prefix).review_shell_present"] == .bool(true))
        #expect(projection.attributes["\(prefix).review_selected_item_present"] == .bool(true))
        #expect(projection.attributes["\(prefix).review_selected_path_present"] == .bool(true))
    }
}
