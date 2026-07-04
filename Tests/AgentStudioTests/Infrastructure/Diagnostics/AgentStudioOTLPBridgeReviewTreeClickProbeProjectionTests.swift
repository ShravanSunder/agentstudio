import Foundation
import Testing

@testable import AgentStudio

extension AgentStudioOTLPBridgeTraceProjectionTests {
    @Test
    func bridgeProjectionPreservesSafeReviewTreeClickProbeDiagnostics() {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 132,
            severityText: .info,
            body: "app.startup_diagnostic_action.blocked",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: [
                "service.name": "AgentStudio"
            ],
            scope: .init(name: "agentstudio.app.startup", version: "0.1.0"),
            attributes: [
                "agentstudio.startup_diagnostic.action": .string("bridge-review-observability-smoke"),
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.dispatch_result": .string(
                    "completed"),
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.rendered_row_count_at_dispatch":
                    .int(8),
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.rendered_row_count_at_find": .int(
                    7),
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.rendered_row_count_delta_before_dispatch":
                    .int(1),
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.second_click_attempted": .bool(
                    false),
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.selection_poll.count": .int(2),
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.selection_poll.last_index":
                    .int(1),
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.selection_poll_trace": .string(
                    "0:private-initial-item|1:private-target-item"),
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.target_row_connected_at_dispatch":
                    .bool(true),
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.target_row_id_at_dispatch":
                    .string("private-target-row"),
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.target_row_id_at_find": .string(
                    "private-target-row"),
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.target_row_path_at_find": .string(
                    "Sources/App/Private.swift"),
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.target_row_same_id_at_dispatch":
                    .bool(true),
                "agentstudio.startup_diagnostic.render_proof.succeeded": .bool(false),
            ]
        )

        let projection = AgentStudioOTLPTraceProjection.project(record)
        let renderedAttributes = projection.attributes.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.dispatch_result"
            ] == .string("completed"))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.rendered_row_count_at_find"
            ] == .int(7))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.rendered_row_count_at_dispatch"
            ] == .int(8))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.rendered_row_count_delta_before_dispatch"
            ] == .int(1))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.selection_poll.count"
            ] == .int(2))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.selection_poll.last_index"
            ] == .int(1))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.target_row_connected_at_dispatch"
            ] == .bool(true))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.target_row_same_id_at_dispatch"
            ] == .bool(true))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.second_click_attempted"
            ] == .bool(false))
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.selection_poll_trace"
            ] == nil)
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.target_row_id_at_find"
            ] == nil)
        #expect(
            projection.attributes[
                "agentstudio.startup_diagnostic.bridge.review_tree_click.probe.target_row_path_at_find"
            ] == nil)
        #expect(!renderedAttributes.contains("private-target-row"))
        #expect(!renderedAttributes.contains("Sources/App/Private.swift"))
    }
}
