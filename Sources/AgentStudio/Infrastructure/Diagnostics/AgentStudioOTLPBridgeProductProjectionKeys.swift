import Foundation

enum BridgeProductStreamProjectionKeys {
    private static let prefix = "agentstudio.startup_diagnostic.bridge.product_stream_webkit"

    static let stringKeys: Set<String> = ["\(prefix).failure.reason"]
    static let numericKeys: Set<String> = Set(
        [
            "total_body_read.count",
            "total_body_read_byte.count",
            "total_decode_call.count",
            "total_provider_call.count",
            "unauthorized_body_read.count",
            "valid_body_byte.count",
            "first_frame_byte.count",
            "frame_receipt.count",
            "cancellation_event.count",
            "active_producer.count",
            "active_producer_task.count",
            "queued_frame.count",
            "maximum_queued_frame.count",
            "producer_overflow.count",
            "post_terminal_frame.count",
        ].map { "\(prefix).\($0)" })
    static let booleanKeys: Set<String> = Set(
        [
            "carrier.succeeded",
            "authentication_before_body.succeeded",
            "body_cap_before_decode.succeeded",
            "strict_route_decode.succeeded",
            "missing_content_length.accepted",
            "exact_request_body_bytes.succeeded",
            "valid_stream_ended",
            "worker_start_post.observed",
            "worker_observed_exact_frames",
            "worker_observed_incremental_frames",
            "framed_stream.succeeded",
            "worker_observed_cancellation",
            "abort_causal_cancellation.succeeded",
        ].map { "\(prefix).\($0)" })
}

enum BridgeProductPaintProjectionKeys {
    private static let prefix = "agentstudio.startup_diagnostic.bridge.product_paint"

    static let stringKeys: Set<String> = Set(
        [
            "comm_session.state",
            "file_mode.latest_dispatch_disposition",
            "file_selection.latest_dispatch_disposition",
            "file_selection.latest_lifecycle_state",
            "page_ready.state",
            "review_selection.latest_dispatch_disposition",
            "review_selection.latest_lifecycle_state",
        ].map { "\(prefix).\($0)" })
    static let numericKeys: Set<String> = Set(
        [
            "comm_session.native_bootstrap_install.count",
            "comm_session.queued_command.count",
            "comm_session.replacement_request.count",
            "decoded_correlation.count",
            "file_mode.send_attempt.count",
            "file_mode.send_synchronous_failure.count",
            "file_source_match.count",
            "painted_element.count",
            "review_candidate.canary.count",
            "review_candidate.digest.count",
            "review_candidate.identity.count",
            "review_candidate.painted_disposition.count",
            "review_candidate.selected_item.count",
            "review_candidate.surface_role.count",
            "review_candidate.whole_position.count",
            "review_metadata_item.count",
            "review_selection.dropped.count",
            "review_selection.first_frame_reached.count",
            "review_selection.initial_requested.count",
            "review_selection.initial_scheduling_accepted.count",
            "review_selection.scheduled.count",
            "review_selection.second_frame_reached.count",
            "review_selection.submitted.count",
            "review_source_match.count",
            "runtime.native_bootstrap_install.accepted.count",
            "runtime.native_bootstrap_install.attempt.count",
            "runtime.native_bootstrap_install.rejected.count",
        ].map { "\(prefix).\($0)" })
    static let booleanKeys: Set<String> = Set(
        [
            "active_mode_review",
            "document_visible",
            "file_identity_chain_matched",
            "file_mode_activated",
            "file_selected_identity_matched",
            "file_source_matched",
            "frame_live",
            "review_identity_chain_matched",
            "review_selected_identity_matched",
            "review_selected_item_present",
            "review_selected_path_present",
            "review_shell_present",
            "review_source_matched",
            "reload_replay_succeeded",
            "worker_replacement_observed",
        ].map { "\(prefix).\($0)" })
}
