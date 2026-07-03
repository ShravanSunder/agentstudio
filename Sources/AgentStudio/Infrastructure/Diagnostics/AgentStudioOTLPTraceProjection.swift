import Foundation

struct AgentStudioOTLPProjectedLogRecord: Equatable, Sendable {
    let timeUnixNano: UInt64
    let severityText: AgentStudioTraceSeverity
    let body: String
    let traceID: String?
    let spanID: String?
    let parentSpanID: String?
    let resource: [String: String]
    let scope: AgentStudioTraceRecord.Scope
    let attributes: [String: AgentStudioTraceValue]
}

enum AgentStudioOTLPTraceProjection {
    static func project(_ record: AgentStudioTraceRecord) -> AgentStudioOTLPProjectedLogRecord {
        let safeResource = safeResource(record.resource)
        let resource = projectedResource(safeResource)
        var attributes = projectedAttributes(record.attributes, resource: safeResource)
        if record.timeUnixNano <= UInt64(Int.max) {
            attributes["agentstudio.event.time_unix_nano"] = .int(Int(record.timeUnixNano))
        }
        return AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: record.timeUnixNano,
            severityText: record.severityText,
            body: safeBody(record.body),
            traceID: validTraceID(record.traceID),
            spanID: validSpanID(record.spanID),
            parentSpanID: validSpanID(record.parentSpanID),
            resource: resource,
            scope: record.scope,
            attributes: attributes
        )
    }

    private static let allowedResourceKeys: Set<String> = [
        "agentstudio.build.config",
        "agentstudio.release_channel",
        "agentstudio.runtime_flavor",
        "agent.proof.launch",
        "agent.proof.marker",
        "dev.build.config",
        "dev.branch.name",
        "dev.release.channel",
        "dev.repo.hash",
        "dev.runtime.flavor",
        "dev.worktree.hash",
        "service.name",
        "service.version",
    ]

    private static let allowedSafeResourceKeys: Set<String> = allowedResourceKeys

    private static let allowedStringAttributeKeys: Set<String> = [
        "agent.proof.marker",
        "agent.proof.launch",
        "agentstudio.app.startup.outcome",
        "agentstudio.app.startup.phase",
        "agentstudio.bridge.cache.result",
        "agentstudio.bridge.content.correlation_mode",
        "agentstudio.bridge.content.interest",
        "agentstudio.bridge.content.priority",
        "agentstudio.bridge.content.role",
        "agentstudio.bridge.content_bytes_bucket",
        "agentstudio.bridge.demand.lane",
        "agentstudio.bridge.diff_row_count_bucket",
        "agentstudio.bridge.file_size_bucket",
        "agentstudio.bridge.fixture_class",
        "agentstudio.bridge.generation.relation",
        "agentstudio.bridge.generation_relation",
        "agentstudio.bridge.intake.frame_kind",
        "agentstudio.bridge.item_count_bucket",
        "agentstudio.bridge.item_update.kind",
        "agentstudio.bridge.language_class",
        "agentstudio.bridge.markdown.fallback_reason",
        "agentstudio.bridge.phase",
        "agentstudio.bridge.plane",
        "agentstudio.bridge.priority",
        "agentstudio.bridge.projection.kind",
        "agentstudio.bridge.protocol",
        "agentstudio.bridge.query_class",
        "agentstudio.bridge.queue.depth_bucket",
        "agentstudio.bridge.result",
        "agentstudio.bridge.result_reason",
        "agentstudio.bridge.rpc.method_class",
        "agentstudio.bridge.scroll_target.kind",
        "agentstudio.bridge.slice",
        "agentstudio.bridge.telemetry.drop_reason",
        "agentstudio.bridge.test.scenario",
        "agentstudio.bridge.transport",
        "agentstudio.bridge.tree_path_count_bucket",
        "agentstudio.bridge.visible_row_bucket",
        "agentstudio.bridge.viewer",
        "agentstudio.bridge.viewer.ttfi_variant",
        "agentstudio.bridge.worker.lane",
        "agentstudio.bridge.worker.task_kind",
        "agentstudio.command.name",
        "agentstudio.command.source",
        "agentstudio.envelope.scope",
        "agentstudio.eventbus.consumer",
        "agentstudio.eventbus.name",
        "agentstudio.ghostty.action.name",
        "agentstudio.ghostty.route.reason",
        "agentstudio.ghostty.signal.class",
        "agentstudio.inbox.claim.lane",
        "agentstudio.inbox.claim.semantic",
        "agentstudio.inbox.decision",
        "agentstudio.inbox.kind",
        "agentstudio.inbox.reason",
        "agentstudio.pane.kind",
        "agentstudio.performance.coordinator.phase",
        "agentstudio.performance.atom.kind",
        "agentstudio.performance.atom.operation",
        "agentstudio.performance.git.backoff.reason",
        "agentstudio.performance.git.status_scope",
        "agentstudio.performance.git.status_unavailable.reason",
        "agentstudio.performance.management_layer.command",
        "agentstudio.performance.pane_action.name",
        "agentstudio.performance.sidebar.toggle.intent",
        "agentstudio.performance.terminal.geometry.reason",
        "agentstudio.performance.terminal.surface.source",
        "agentstudio.persistence.backend",
        "agentstudio.persistence.lane",
        "agentstudio.persistence.operation",
        "agentstudio.persistence.outcome",
        "agentstudio.persistence.phase",
        "agentstudio.persistence.recovery.kind",
        "agentstudio.runtime.action_policy",
        "agentstudio.runtime.event",
        "agentstudio.sqlite.database",
        "agentstudio.startup_diagnostic.action",
        "agentstudio.startup_diagnostic.bridge.file_view.expected_bootstrap.protocol",
        "agentstudio.startup_diagnostic.bridge.file_view.bootstrap.protocol",
        "agentstudio.startup_diagnostic.bridge.file_view.bootstrap.source_spec.state",
        "agentstudio.startup_diagnostic.bridge.file_view.native_probe.last_frame_kind",
        "agentstudio.startup_diagnostic.bridge.file_view.native_probe.last_reason",
        "agentstudio.startup_diagnostic.bridge.file_view.native_probe.last_receiver_reason",
        "agentstudio.startup_diagnostic.bridge.file_view.tree_extent.kind",
        "agentstudio.startup_diagnostic.bridge.selected_content.state",
        "agentstudio.startup_diagnostic.bridge.selected_change_kind",
        "agentstudio.startup_diagnostic.bridge.selected_content.roles",
        "agentstudio.startup_diagnostic.bridge.modified_click.selected_change_kind",
        "agentstudio.startup_diagnostic.bridge.modified_click.selected_content_state",
        "agentstudio.startup_diagnostic.bridge.modified_click.selected_content.roles",
        "agentstudio.startup_diagnostic.bridge.modified_click.selected_materialized.item_type",
        "agentstudio.startup_diagnostic.bridge.modified_click.set_filter.reason",
        "agentstudio.startup_diagnostic.bridge.modified_click.set_filter.status",
        "agentstudio.startup_diagnostic.bridge.review_tree_click.selected_content_state",
        "agentstudio.startup_diagnostic.bridge.review_tree_click.selected_materialized.item_type",
        "agentstudio.startup_diagnostic.bridge.review_intake.last_frame_kind",
        "agentstudio.startup_diagnostic.bridge.file_view.open_file.state",
        "agentstudio.startup_diagnostic.bridge.file_view.source.state",
        "agentstudio.startup_diagnostic.bridge.page_issue.last_class",
        "agentstudio.startup_diagnostic.bridge.page_issue.last_kind",
        "agentstudio.startup_diagnostic.bridge.review_canvas.branch",
        "agentstudio.startup_diagnostic.bridge.review_shell.selected_content.state",
        "agentstudio.startup_diagnostic.bridge.review_shell.state",
        "agentstudio.startup_diagnostic.bridge.selected_demand.load_failure.kind",
        "agentstudio.startup_diagnostic.bridge.selected_demand.result.reason",
        "agentstudio.startup_diagnostic.bridge.selected_demand.result.status",
        "agentstudio.startup_diagnostic.bridge.diff_container.display",
        "agentstudio.startup_diagnostic.bridge.code_view.rendered_item.element.first_child.tag",
        "agentstudio.startup_diagnostic.bridge.code_view.rendered_item.type",
        "agentstudio.startup_diagnostic.bridge.code_view_scroll_owner.first_child.tag",
        "agentstudio.startup_diagnostic.bridge.selected_materialized.item_type",
        "agentstudio.startup_diagnostic.bridge.selected_materialized.update_result",
        "agentstudio.startup_diagnostic.bridge.worker_pool.init_probe.failure_reason",
        "agentstudio.startup_diagnostic.bridge.worker_pool.init_probe.stage",
        "agentstudio.startup_diagnostic.bridge.worker_pool.manager_state",
        "agentstudio.startup_diagnostic.bridge.worker_pool.state",
        "agentstudio.startup_diagnostic.bridge.worker_diagnostic.bootstrap_state",
        "agentstudio.startup_diagnostic.bridge.worker_diagnostic.initialize_request_id_state",
        "agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_failure_kind",
        "agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_forward_result",
        "agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_message_type",
        "agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_request_type",
        "agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_success_id_prefix",
        "agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_success_id_state",
        "agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_success_matches_initialize_request",
        "agentstudio.startup_diagnostic.bridge.worker_diagnostic.last_success_request_type",
        "agentstudio.startup_diagnostic.skip_reason",
        "agentstudio.terminal.startup.outcome",
        "agentstudio.terminal.startup.failure.kind",
        "agentstudio.terminal.startup.phase",
        "agentstudio.trace.tag",
        "agentstudio.workspace.boot.step",
        "agentstudio.zmx.startup.inventory_outcome",
        "dev.runtime.flavor",
        "dev.branch.name",
        "terminal.activity.close_reason",
        "terminal.activity.source",
    ]

    private static let allowedNumericAttributeKeys: Set<String> = [
        "agentstudio.bridge.batch.sample_count",
        "agentstudio.bridge.content.byte_count",
        "agentstudio.bridge.content.byte_length",
        "agentstudio.bridge.content.byte_size_bucket",
        "agentstudio.bridge.content.body_registry_commit_ms",
        "agentstudio.bridge.content.chunk_byte_count",
        "agentstudio.bridge.content.chunk_count",
        "agentstudio.bridge.content.estimated_bytes",
        "agentstudio.bridge.content.first_chunk_wait_ms",
        "agentstudio.bridge.content.line_count_bucket",
        "agentstudio.bridge.content.response_wait_ms",
        "agentstudio.bridge.content.resource_count",
        "agentstudio.bridge.content.stream_read_ms",
        "agentstudio.bridge.content.total_bytes_read",
        "agentstudio.bridge.demand.active.count",
        "agentstudio.bridge.demand.deferred.count",
        "agentstudio.bridge.demand.duration_ms",
        "agentstudio.bridge.demand.enqueue_accepted.count",
        "agentstudio.bridge.demand.enqueue_rejected.count",
        "agentstudio.bridge.demand.executor_in_flight_ms",
        "agentstudio.bridge.demand.executor_pending_wait_ms",
        "agentstudio.bridge.demand.failed.count",
        "agentstudio.bridge.demand.foreground.count",
        "agentstudio.bridge.demand.idle.count",
        "agentstudio.bridge.demand.intent.count",
        "agentstudio.bridge.demand.loaded.count",
        "agentstudio.bridge.demand.nearby.count",
        "agentstudio.bridge.demand.request.sequence",
        "agentstudio.bridge.demand.overflow_drop.count",
        "agentstudio.bridge.demand.job_execution_ms",
        "agentstudio.bridge.demand.queue_depth",
        "agentstudio.bridge.demand.scheduler_queue_wait_ms",
        "agentstudio.bridge.demand.speculative.count",
        "agentstudio.bridge.demand.stale_drop.count",
        "agentstudio.bridge.demand.visible.count",
        "agentstudio.bridge.intake.generation",
        "agentstudio.bridge.intake.sequence",
        "agentstudio.bridge.markdown.input_bytes",
        "agentstudio.bridge.markdown.output_bytes",
        "agentstudio.bridge.metadata_manifest.emitted_total",
        "agentstudio.bridge.metadata_manifest.expected_total",
        "agentstudio.bridge.metadata_manifest.remaining_total",
        "agentstudio.bridge.review.item_count",
        "agentstudio.bridge.source.generation",
        "agentstudio.bridge.selected_content.click_to_paint_ms",
        "agentstudio.bridge.selected_content.frame_wait_ms",
        "agentstudio.bridge.selected_content.materialize_ms",
        "agentstudio.bridge.telemetry.dropped_count",
        "agentstudio.bridge.visible_item.count",
        "agentstudio.bridge.worktree_file.pending_frame.count",
        "agentstudio.bridge.worktree_file.tree.all_row.count",
        "agentstudio.bridge.worktree_file.tree.current_row.count",
        "agentstudio.bridge.worktree_file.tree.descriptor.count",
        "agentstudio.bridge.worktree_file.tree.discovered_row.count",
        "agentstudio.bridge.worktree_file.tree.first_sequence",
        "agentstudio.bridge.worktree_file.tree.incoming_frame.count",
        "agentstudio.bridge.worktree_file.tree.initial_row.count",
        "agentstudio.bridge.worktree_file.tree.window.dispatch_elapsed_ms",
        "agentstudio.bridge.worktree_file.tree.window.prepare_elapsed_ms",
        "agentstudio.bridge.worktree_file.tree.window.row.count",
        "agentstudio.bridge.worktree_file.tree.window.sequence",
        "agentstudio.bridge.worktree_file.tree.window.start_index",
        "agentstudio.bridge.worktree_file.tree.window.count",
        "agentstudio.display.count",
        "agentstudio.envelope.schema_version",
        "agentstudio.envelope.seq",
        "agentstudio.ghostty.action.tag",
        "agentstudio.ghostty.status",
        "agentstudio.inbox.global_unread_after",
        "agentstudio.inbox.global_unread_before",
        "agentstudio.inbox.global_unread_count",
        "agentstudio.pane_inbox.cleared_count",
        "agentstudio.pane_inbox.keep_count",
        "agentstudio.performance.atom.accepted_change.count",
        "agentstudio.performance.atom.cached_key.count",
        "agentstudio.performance.atom.input_revision.count",
        "agentstudio.performance.atom.slot.count",
        "agentstudio.performance.commandbar.input.count",
        "agentstudio.performance.commandbar.item.count",
        "agentstudio.performance.commandbar.pane.count",
        "agentstudio.performance.commandbar.query_character.count",
        "agentstudio.performance.commandbar.repo.count",
        "agentstudio.performance.commandbar.result.count",
        "agentstudio.performance.commandbar.worktree.count",
        "agentstudio.performance.coordinator.active_pane_write.count",
        "agentstudio.performance.coordinator.activity_write.count",
        "agentstudio.performance.coordinator.derived_envelope.count",
        "agentstudio.performance.coordinator.filesystem_source_elapsed_ms",
        "agentstudio.performance.coordinator.index_elapsed_ms",
        "agentstudio.performance.coordinator.mainactor_apply_elapsed_ms",
        "agentstudio.performance.coordinator.pane.count",
        "agentstudio.performance.coordinator.registered.count",
        "agentstudio.performance.coordinator.total_elapsed_ms",
        "agentstudio.performance.coordinator.unregistered.count",
        "agentstudio.performance.coordinator.worktree.count",
        "agentstudio.performance.elapsed_ms",
        "agentstudio.performance.git.admitted.count",
        "agentstudio.performance.git.available_slot.count",
        "agentstudio.performance.git.backoff_attempt.count",
        "agentstudio.performance.git.backoff_ms",
        "agentstudio.performance.git.dropped_subscriber.count",
        "agentstudio.performance.git.enqueued.count",
        "agentstudio.performance.git.event_posted.count",
        "agentstudio.performance.git.input_path.count",
        "agentstudio.performance.git.pathspec.count",
        "agentstudio.performance.git.pending.count",
        "agentstudio.performance.git.registered.count",
        "agentstudio.performance.git.running.count",
        "agentstudio.performance.git.snapshot_dedup.count",
        "agentstudio.performance.git.status.duration_ms",
        "agentstudio.performance.git.status.elapsed_ms",
        "agentstudio.performance.git.suppressed_git_internal_path.count",
        "agentstudio.performance.git.suppressed_ignored_path.count",
        "agentstudio.performance.git.tick.count",
        "agentstudio.ghostty.surface.environment_variable_count",
        "agentstudio.ghostty.surface.initial_frame_height",
        "agentstudio.ghostty.surface.initial_frame_width",
        "agentstudio.performance.management_layer.pane.count",
        "agentstudio.performance.management_layer.tab.count",
        "agentstudio.performance.pane_action.pane.count",
        "agentstudio.performance.pane_action.tab.count",
        "agentstudio.performance.pane_tab_layout.pane.count",
        "agentstudio.performance.pane_tab_layout.subview.count",
        "agentstudio.performance.pane_tab_layout.tab.count",
        "agentstudio.performance.pane_view_restore.pane.count",
        "agentstudio.performance.pane_view_restore.tab.count",
        "agentstudio.performance.pane_view_restore.visible_pane.count",
        "agentstudio.performance.sidebar.expanded_group.count",
        "agentstudio.performance.sidebar.group.count",
        "agentstudio.performance.sidebar.loading_repo.count",
        "agentstudio.performance.sidebar.query_character.count",
        "agentstudio.performance.sidebar.repo.count",
        "agentstudio.performance.sidebar.split_width",
        "agentstudio.performance.sidebar.width",
        "agentstudio.performance.tabbar.pane.count",
        "agentstudio.performance.tabbar.source_tab.count",
        "agentstudio.performance.tabbar.tab.count",
        "agentstudio.performance.terminal.geometry.visible_terminal.count",
        "agentstudio.performance.terminal.surface.cell_height_px",
        "agentstudio.performance.terminal.surface.cell_width_px",
        "agentstudio.performance.terminal.surface.column.count",
        "agentstudio.performance.terminal.surface.current_height_px",
        "agentstudio.performance.terminal.surface.current_width_px",
        "agentstudio.performance.terminal.surface.requested_height_px",
        "agentstudio.performance.terminal.surface.requested_width_px",
        "agentstudio.performance.terminal.surface.row.count",
        "agentstudio.performance.topology.index.count",
        "agentstudio.startup_diagnostic.created_pane.count",
        "agentstudio.startup_diagnostic.expected_visible_pane.count",
        "agentstudio.startup_diagnostic.bridge.code_line.count",
        "agentstudio.startup_diagnostic.bridge.code_line_with_data_line.count",
        "agentstudio.startup_diagnostic.bridge.code_shadow_text.length",
        "agentstudio.startup_diagnostic.bridge.code_text.length",
        "agentstudio.startup_diagnostic.bridge.bridge_command.count",
        "agentstudio.startup_diagnostic.bridge.bridge_response.count",
        "agentstudio.startup_diagnostic.bridge.code_view.instance.first_item.height_px",
        "agentstudio.startup_diagnostic.bridge.code_view.instance.first_item.top_px",
        "agentstudio.startup_diagnostic.bridge.code_view.instance.height_px",
        "agentstudio.startup_diagnostic.bridge.code_view.instance.item.count",
        "agentstudio.startup_diagnostic.bridge.code_view.instance.render_state.first_index",
        "agentstudio.startup_diagnostic.bridge.code_view.instance.render_state.last_index",
        "agentstudio.startup_diagnostic.bridge.code_view.instance.scroll_height_px",
        "agentstudio.startup_diagnostic.bridge.code_view.instance.window.bottom_px",
        "agentstudio.startup_diagnostic.bridge.code_view.instance.window.top_px",
        "agentstudio.startup_diagnostic.bridge.code_view.rendered_item.count",
        "agentstudio.startup_diagnostic.bridge.code_view.rendered_item.element.child.count",
        "agentstudio.startup_diagnostic.bridge.code_view.rendered_item.element.height_px",
        "agentstudio.startup_diagnostic.bridge.code_view.rendered_item.version",
        "agentstudio.startup_diagnostic.bridge.code_view_scroll_owner.child.count",
        "agentstudio.startup_diagnostic.bridge.code_view_scroll_owner.height_px",
        "agentstudio.startup_diagnostic.bridge.code_view_scroll_owner.scroll_height_px",
        "agentstudio.startup_diagnostic.bridge.code_view_panel.height_px",
        "agentstudio.startup_diagnostic.bridge.code_view_panel.width_px",
        "agentstudio.startup_diagnostic.bridge.diff_container.count",
        "agentstudio.startup_diagnostic.bridge.diff_container.height_px",
        "agentstudio.startup_diagnostic.bridge.diff_container.offset_height_px",
        "agentstudio.startup_diagnostic.bridge.diff_container.pre.count",
        "agentstudio.startup_diagnostic.bridge.diff_container.pre.height_px",
        "agentstudio.startup_diagnostic.bridge.diff_container.pre_text.length",
        "agentstudio.startup_diagnostic.bridge.diff_container.scroll_height_px",
        "agentstudio.startup_diagnostic.bridge.diff_container.shadow_child.count",
        "agentstudio.startup_diagnostic.bridge.diff_container.width_px",
        "agentstudio.startup_diagnostic.bridge.file_view.bootstrap.source_spec.length",
        "agentstudio.startup_diagnostic.bridge.file_view.body_preview.length",
        "agentstudio.startup_diagnostic.bridge.file_view.bridge_command.count",
        "agentstudio.startup_diagnostic.bridge.file_view.bridge_response.count",
        "agentstudio.startup_diagnostic.bridge.file_view.click.body_preview.length",
        "agentstudio.startup_diagnostic.bridge.file_view.second_click.body_preview.length",
        "agentstudio.startup_diagnostic.bridge.file_view.offscreen_click.body_preview.length",
        "agentstudio.startup_diagnostic.bridge.file_view.code_text.length",
        "agentstudio.startup_diagnostic.bridge.file_view.code_view.height_px",
        "agentstudio.startup_diagnostic.bridge.file_view.code_view.width_px",
        "agentstudio.startup_diagnostic.bridge.file_view.descriptor.count",
        "agentstudio.startup_diagnostic.bridge.file_view.descriptor_request_command.count",
        "agentstudio.startup_diagnostic.bridge.file_view.intake_frame.count",
        "agentstudio.startup_diagnostic.bridge.file_view.intake_ready_command.count",
        "agentstudio.startup_diagnostic.bridge.file_view.metadata_file_row.count",
        "agentstudio.startup_diagnostic.bridge.file_view.metadata_tree_row.count",
        "agentstudio.startup_diagnostic.bridge.file_view.mode_switch.count",
        "agentstudio.startup_diagnostic.bridge.file_view.native_probe.count",
        "agentstudio.startup_diagnostic.bridge.file_view.native_probe.last_generation",
        "agentstudio.startup_diagnostic.bridge.file_view.native_probe.last_sequence",
        "agentstudio.startup_diagnostic.bridge.file_view.open_source_command.count",
        "agentstudio.startup_diagnostic.bridge.file_view.tree_path.count",
        "agentstudio.startup_diagnostic.bridge.file_view.tree_scroll_stress.count",
        "agentstudio.startup_diagnostic.bridge.file_view.total_descriptor.count",
        "agentstudio.startup_diagnostic.bridge.file_view.tree.height_px",
        "agentstudio.startup_diagnostic.bridge.page_issue.count",
        "agentstudio.startup_diagnostic.bridge.page_issue.disallowed.count",
        "agentstudio.startup_diagnostic.bridge.review_expected_item.count",
        "agentstudio.startup_diagnostic.bridge.intake_frame.count",
        "agentstudio.startup_diagnostic.bridge.review_intake_metadata_window_frame.count",
        "agentstudio.startup_diagnostic.bridge.review_intake_ready_command.count",
        "agentstudio.startup_diagnostic.bridge.review_intake_snapshot_frame.count",
        "agentstudio.startup_diagnostic.bridge.review_metadata_item.count",
        "agentstudio.startup_diagnostic.bridge.review_metadata_tree_row.count",
        "agentstudio.startup_diagnostic.bridge.review_tree.client_height_px",
        "agentstudio.startup_diagnostic.bridge.review_tree.scroll_height_px",
        "agentstudio.startup_diagnostic.bridge.review_tree_scroll_stress.count",
        "agentstudio.startup_diagnostic.bridge.review_tree_click.click_attempt.count",
        "agentstudio.startup_diagnostic.bridge.review_tree_click.rendered_row.count",
        "agentstudio.startup_diagnostic.bridge.modified_click.click_attempt.count",
        "agentstudio.startup_diagnostic.bridge.modified_click.rendered_row.count",
        "agentstudio.startup_diagnostic.bridge.review_tree_click.selected_content_character.count",
        "agentstudio.startup_diagnostic.bridge.review_tree_click.selected_materialized.item_version",
        "agentstudio.startup_diagnostic.bridge.review_tree_click.target_row.index",
        "agentstudio.startup_diagnostic.bridge.modified_click.selected_content_character.count",
        "agentstudio.startup_diagnostic.bridge.modified_click.selected_materialized.item_version",
        "agentstudio.startup_diagnostic.bridge.worker_pool.active_tasks",
        "agentstudio.startup_diagnostic.bridge.worker_pool.busy_workers",
        "agentstudio.startup_diagnostic.bridge.worker_pool.diff_cache_size",
        "agentstudio.startup_diagnostic.bridge.worker_pool.file_cache_size",
        "agentstudio.startup_diagnostic.bridge.worker_pool.init_probe.language_count",
        "agentstudio.startup_diagnostic.bridge.worker_pool.init_probe.theme_count",
        "agentstudio.startup_diagnostic.bridge.worker_diagnostic.diff_success_count",
        "agentstudio.startup_diagnostic.bridge.worker_diagnostic.failure_count",
        "agentstudio.startup_diagnostic.bridge.worker_diagnostic.file_success_count",
        "agentstudio.startup_diagnostic.bridge.worker_diagnostic.forwarded_message_count",
        "agentstudio.startup_diagnostic.bridge.worker_diagnostic.initialize_success_count",
        "agentstudio.startup_diagnostic.bridge.worker_diagnostic.success_count",
        "agentstudio.startup_diagnostic.bridge.worker_pool.queued_tasks",
        "agentstudio.startup_diagnostic.bridge.worker_pool.total_workers",
        "agentstudio.startup_diagnostic.bridge.selected_content_cache_key.count",
        "agentstudio.startup_diagnostic.bridge.selected_content_character.count",
        "agentstudio.startup_diagnostic.bridge.selected_content_line.count",
        "agentstudio.startup_diagnostic.bridge.selected_content_role.count",
        "agentstudio.startup_diagnostic.bridge.selected_demand.deferred.count",
        "agentstudio.startup_diagnostic.bridge.selected_demand.failed.count",
        "agentstudio.startup_diagnostic.bridge.selected_demand.loaded.count",
        "agentstudio.startup_diagnostic.bridge.selected_materialized.addition_line.count",
        "agentstudio.startup_diagnostic.bridge.selected_materialized.deletion_line.count",
        "agentstudio.startup_diagnostic.bridge.selected_materialized.file_line.count",
        "agentstudio.startup_diagnostic.bridge.selected_materialized.item_version",
        "agentstudio.startup_diagnostic.fixture.surface.count",
        "agentstudio.startup_diagnostic.fixture.surface_reference.count",
        "agentstudio.startup_diagnostic.fixture.terminal_view.count",
        "agentstudio.startup_diagnostic.fixture.valid_geometry.count",
        "agentstudio.terminal.startup.failure.creation_retry.count",
        "agentstudio.workspace.snapshot.pane_count",
        "agentstudio.zmx.startup.hydrated_anchor_count",
        "agentstudio.zmx.startup.live_session_count",
        "agentstudio.zmx.startup.protected_session_count",
        "agentstudio.zmx.startup.unmatched_live_session_count",
        "agentstudio.zmx.startup.unresolved_candidate_count",
        "agentstudio.zmx.socket_path_headroom",
        "terminal.activity.baseline_rows",
        "terminal.activity.debounce_ms",
        "terminal.activity.duration_ms",
        "terminal.activity.event_count",
        "terminal.activity.latest_rows",
        "terminal.activity.rows_added",
        "terminal.activity.threshold_rows",
    ]

    private static let allowedBooleanAttributeKeys: Set<String> = [
        "agentstudio.app.is_active",
        "agentstudio.bridge.cache_hit",
        "agentstudio.bridge.content.binary",
        "agentstudio.bridge.content.stale",
        "agentstudio.bridge.worktree_file.tree.window.is_final",
        "agentstudio.bridge.header_missing",
        "agentstudio.bridge.header_supported",
        "agentstudio.bridge.selected",
        "agentstudio.ghostty.route.result",
        "agentstudio.inbox.notification.coalesced",
        "agentstudio.inbox.notification.revoked",
        "agentstudio.pane.attended",
        "agentstudio.pane.observed",
        "agentstudio.pane.pinned_to_bottom",
        "agentstudio.pane_inbox.dismissed",
        "agentstudio.performance.atom.cache_hit",
        "agentstudio.performance.git.backoff_open",
        "agentstudio.performance.git.has_git_internal_changes",
        "agentstudio.ghostty.surface.initial_frame_present",
        "agentstudio.ghostty.surface.startup_command_present",
        "agentstudio.performance.management_layer.did_exit",
        "agentstudio.performance.management_layer.is_active",
        "agentstudio.performance.pane_view_restore.force_when_bounds_exist",
        "agentstudio.performance.pane_view_restore.had_placeholder",
        "agentstudio.performance.sidebar.is_collapsed",
        "agentstudio.performance.sidebar.is_filtering",
        "agentstudio.performance.sidebar.was_empty",
        "agentstudio.performance.sidebar.was_collapsed",
        "agentstudio.performance.terminal.surface.dedup_likely",
        "agentstudio.performance.terminal.surface.hidden",
        "agentstudio.performance.terminal.surface.has_superview",
        "agentstudio.performance.terminal.surface.has_window",
        "agentstudio.performance.topology.has_match",
        "agentstudio.startup_diagnostic.bridge.code_view.visible",
        "agentstudio.startup_diagnostic.bridge.file_view.click.open_file_matches",
        "agentstudio.startup_diagnostic.bridge.file_view.click.rendered_file_matches",
        "agentstudio.startup_diagnostic.bridge.file_view.click.selected_matches",
        "agentstudio.startup_diagnostic.bridge.file_view.click.target_found",
        "agentstudio.startup_diagnostic.bridge.file_view.second_click.open_file_matches",
        "agentstudio.startup_diagnostic.bridge.file_view.second_click.rendered_file_matches",
        "agentstudio.startup_diagnostic.bridge.file_view.second_click.selected_matches",
        "agentstudio.startup_diagnostic.bridge.file_view.second_click.target_found",
        "agentstudio.startup_diagnostic.bridge.file_view.offscreen_click.open_file_matches",
        "agentstudio.startup_diagnostic.bridge.file_view.offscreen_click.rendered_file_matches",
        "agentstudio.startup_diagnostic.bridge.file_view.offscreen_click.selected_matches",
        "agentstudio.startup_diagnostic.bridge.file_view.offscreen_click.target_found",
        "agentstudio.startup_diagnostic.bridge.file_view.code_view.visible",
        "agentstudio.startup_diagnostic.bridge.file_view.mode_switch.final_file_selected",
        "agentstudio.startup_diagnostic.bridge.file_view.native_probe.last_stream_id_matches",
        "agentstudio.startup_diagnostic.bridge.file_view.shell.visible",
        "agentstudio.startup_diagnostic.bridge.file_view.tree_scroll_stress.reached_bottom",
        "agentstudio.startup_diagnostic.bridge.file_view.tree.visible",
        "agentstudio.startup_diagnostic.bridge.file_view.tree_full_stream.satisfied",
        "agentstudio.startup_diagnostic.bridge.modified_click.filter_requested",
        "agentstudio.startup_diagnostic.bridge.modified_click.first_rendered_present",
        "agentstudio.startup_diagnostic.bridge.modified_click.selected_matches_target",
        "agentstudio.startup_diagnostic.bridge.modified_click.shell_selected_matches_target",
        "agentstudio.startup_diagnostic.bridge.modified_click.selected_content.cache_keys_present",
        "agentstudio.startup_diagnostic.bridge.modified_click.target_found",
        "agentstudio.startup_diagnostic.bridge.review_metadata.converged",
        "agentstudio.startup_diagnostic.bridge.review_tree_scroll_stress.reached_bottom",
        "agentstudio.startup_diagnostic.bridge.review_tree_click.selected_matches_target",
        "agentstudio.startup_diagnostic.bridge.review_tree_click.target_row.visible",
        "agentstudio.startup_diagnostic.bridge.review_intake.last_stream_id_matches",
        "agentstudio.startup_diagnostic.bridge.review_shell.visible",
        "agentstudio.startup_diagnostic.bridge.review_shell.selected_path.visible",
        "agentstudio.startup_diagnostic.bridge.selected_content.cache_keys_present",
        "agentstudio.startup_diagnostic.bridge.selected_content.visible",
        "agentstudio.startup_diagnostic.bridge.selected_item.visible",
        "agentstudio.startup_diagnostic.bridge.selected_path.visible",
        "agentstudio.startup_diagnostic.bridge.worker_pool.workers_failed",
        "agentstudio.startup_diagnostic.render_proof.succeeded",
        "agentstudio.workspace.snapshot.has_tab_membership_mismatch",
        "terminal.activity.is_agent_candidate",
        "terminal.activity.is_agent_settled_candidate",
        "terminal.activity.is_inferred",
        "terminal.activity.is_pinned_to_bottom",
    ]

    private static let resourceKeysProjectedAsLogAttributes: Set<String> = [
        "agentstudio.release_channel",
        "agentstudio.runtime_flavor",
        "agent.proof.launch",
        "agent.proof.marker",
        "dev.release.channel",
        "dev.repo.hash",
        "dev.runtime.flavor",
        "dev.worktree.hash",
        "dev.branch.name",
        "service.version",
    ]

    private static func safeResource(_ resource: [String: String]) -> [String: String] {
        var projected: [String: String] = [:]
        for (key, value) in resource where allowedSafeResourceKeys.contains(key) && isSafeResourceValue(value) {
            projected[key] = value
        }
        return projected
    }

    private static func projectedResource(_ safeResource: [String: String]) -> [String: String] {
        safeResource.filter { key, _ in
            allowedResourceKeys.contains(key)
        }
    }

    private static func projectedAttributes(
        _ attributes: [String: AgentStudioTraceValue],
        resource: [String: String]
    ) -> [String: AgentStudioTraceValue] {
        var projected: [String: AgentStudioTraceValue] = [:]
        for (key, value) in attributes {
            guard let value = projectedAttributeValue(key: key, value: value) else {
                continue
            }
            projected[key] = value
        }
        for (key, value) in resource where resourceKeysProjectedAsLogAttributes.contains(key) {
            projected[key] = .string(value)
        }
        return projected
    }

    private static func projectedAttributeValue(
        key: String,
        value: AgentStudioTraceValue
    ) -> AgentStudioTraceValue? {
        guard !isIdentifierKey(key), !isErrorKey(key) else {
            return nil
        }

        switch value {
        case .string(let stringValue):
            guard
                !isPayloadKey(key),
                allowedStringAttributeKeys.contains(key),
                isSafeControlledString(stringValue),
                isAllowedControlledStringValue(key: key, value: stringValue)
            else { return nil }
            return .string(stringValue)
        case .int:
            return isAllowedNumericKey(key) ? value : nil
        case .double:
            return isAllowedNumericKey(key) ? value : nil
        case .bool:
            return isAllowedBooleanKey(key) ? value : nil
        case .stringArray:
            return nil
        }
    }

    private static func isAllowedNumericKey(_ key: String) -> Bool {
        allowedNumericAttributeKeys.contains(key)
    }

    private static func isAllowedBooleanKey(_ key: String) -> Bool {
        allowedBooleanAttributeKeys.contains(key)
    }

    private static func isIdentifierKey(_ key: String) -> Bool {
        let normalizedKey = key.lowercased()
        return normalizedKey.hasSuffix(".id")
            || normalizedKey.contains(".id.")
            || normalizedKey.hasSuffix("_id")
            || normalizedKey.contains("_id.")
    }

    private static func isErrorKey(_ key: String) -> Bool {
        key.lowercased().contains("error")
    }

    private static func isPayloadKey(_ key: String) -> Bool {
        let normalizedKey = key.lowercased()
        return normalizedKey.contains("path")
            || normalizedKey.contains("payload")
            || normalizedKey.contains("prompt")
            || normalizedKey.contains("output")
            || normalizedKey.contains("text")
    }

    private static func safeBody(_ body: String) -> String {
        isSafeEventName(body) ? body : "agentstudio.trace.record"
    }

    private static func isSafeEventName(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "."
                || scalar == "_"
                || scalar == "-"
                || scalar == ":"
        }
    }

    private static func isSafeControlledString(_ value: String) -> Bool {
        isSafeEventName(value)
    }

    private static func isAllowedControlledStringValue(key: String, value: String) -> Bool {
        if let allowedValues = BridgeTelemetryBatchValidator.allowedStringValuesByAttributeKey[key] {
            return allowedValues.contains(value)
        }
        return true
    }

    private static func isSafeResourceValue(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 160 else {
            return false
        }

        let normalizedValue = value.lowercased()
        return !normalizedValue.hasPrefix("/")
            && !normalizedValue.contains("/users/")
            && !normalizedValue.contains("://")
            && !normalizedValue.contains("\\")
            && !normalizedValue.contains("\n")
            && !normalizedValue.contains("\r")
    }

    private static func validTraceID(_ value: String?) -> String? {
        validHexIdentifier(value, requiredLength: 32)
    }

    private static func validSpanID(_ value: String?) -> String? {
        validHexIdentifier(value, requiredLength: 16)
    }

    private static func validHexIdentifier(_ value: String?, requiredLength: Int) -> String? {
        guard let value, value.count == requiredLength else {
            return nil
        }
        guard value.utf8.contains(where: { $0 != 48 }) else {
            return nil
        }
        guard
            value.utf8.allSatisfy({ byte in
                byte >= 48 && byte <= 57 || byte >= 97 && byte <= 102
            })
        else {
            return nil
        }
        return value
    }
}
