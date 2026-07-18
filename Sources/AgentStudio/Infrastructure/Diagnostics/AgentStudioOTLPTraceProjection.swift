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
        "agentstudio.bridge.content.role",
        "agentstudio.bridge.generation.relation",
        "agentstudio.bridge.phase",
        "agentstudio.bridge.plane",
        "agentstudio.bridge.priority",
        "agentstudio.bridge.rpc.method_class",
        "agentstudio.bridge.slice",
        "agentstudio.bridge.telemetry.drop_reason",
        "agentstudio.bridge.test.scenario",
        "agentstudio.bridge.transport",
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
        "agentstudio.preferences.global.status",
        "agentstudio.performance.coordinator.phase",
        "agentstudio.performance.atom.kind",
        "agentstudio.performance.atom.operation",
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
        "agentstudio.startup_diagnostic.skip_reason",
        "agentstudio.terminal.startup.outcome",
        "agentstudio.terminal.startup.failure.kind",
        "agentstudio.terminal.startup.phase",
        "agentstudio.tcc.access.result",
        "agentstudio.tcc.access.target",
        "agentstudio.tcc.bundle.kind",
        "agentstudio.tcc.code_identity.kind",
        "agentstudio.tcc.command.exit_class",
        "agentstudio.tcc.phase",
        "agentstudio.tcc.responsible.kind",
        "agentstudio.tcc.subject",
        "agentstudio.trace.tag",
        "agentstudio.workspace.boot.step",
        "dev.runtime.flavor",
        "dev.branch.name",
        "terminal.activity.close_reason",
        "terminal.activity.source",
    ]

    private static let allowedNumericAttributeKeys: Set<String> = [
        "agentstudio.bridge.batch.sample_count",
        "agentstudio.bridge.content.byte_size_bucket",
        "agentstudio.bridge.content.line_count_bucket",
        "agentstudio.bridge.telemetry.dropped_count",
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
        "agentstudio.preferences.global.load_elapsed_ms",
        "agentstudio.preferences.global.schema_version",
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
        "agentstudio.performance.filesystem.drain_task.count",
        "agentstudio.performance.filesystem.logical_debt.count",
        "agentstudio.performance.filesystem.pending_worktree.count",
        "agentstudio.performance.filesystem.watched_folder.active.count",
        "agentstudio.performance.filesystem.watched_folder.dirty_follow_up.count",
        "agentstudio.performance.filesystem.watched_folder.ready.count",
        "agentstudio.performance.git.admitted.count",
        "agentstudio.performance.git.available_slot.count",
        "agentstudio.performance.git.dropped_subscriber.count",
        "agentstudio.performance.git.enqueued.count",
        "agentstudio.performance.git.event_posted.count",
        "agentstudio.performance.git.input_path.count",
        "agentstudio.performance.git.logical_debt.count",
        "agentstudio.performance.git.logical_pending.count",
        "agentstudio.performance.git.logical_running.count",
        "agentstudio.performance.git.pending.count",
        "agentstudio.performance.git.registered.count",
        "agentstudio.performance.git.retry_pending.count",
        "agentstudio.performance.git.running.count",
        "agentstudio.performance.git.snapshot_dedup.count",
        "agentstudio.performance.git.status.duration_ms",
        "agentstudio.performance.git.status.elapsed_ms",
        "agentstudio.performance.git.suppressed_git_internal_path.count",
        "agentstudio.performance.git.suppressed_ignored_path.count",
        "agentstudio.performance.git.tick.count",
        "agentstudio.performance.process.malloc.blocks_in_use",
        "agentstudio.performance.process.malloc.maximum_size_in_use_bytes",
        "agentstudio.performance.process.malloc.size_allocated_bytes",
        "agentstudio.performance.process.malloc.size_in_use_bytes",
        "agentstudio.performance.runtime_delivery.eventbus_active_delivery_debt.count",
        "agentstudio.performance.runtime_delivery.eventbus_active_subscriber.count",
        "agentstudio.performance.runtime_delivery.eventbus_live_dropped.count",
        "agentstudio.performance.runtime_delivery.eventbus_replay_dropped.count",
        "agentstudio.performance.runtime_delivery.eventbus_retired_undelivered.count",
        "agentstudio.performance.runtime_delivery.runtime_channel_outbound_dropped.count",
        "agentstudio.performance.runtime_delivery.runtime_channel_outbound_pending.count",
        "agentstudio.performance.runtime_delivery.runtime_channel_retired_undelivered.count",
        "agentstudio.performance.runtime_delivery.total_pending.count",
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
        "agentstudio.startup_diagnostic.fixture.surface.count",
        "agentstudio.startup_diagnostic.fixture.surface_reference.count",
        "agentstudio.startup_diagnostic.fixture.terminal_view.count",
        "agentstudio.startup_diagnostic.fixture.valid_geometry.count",
        "agentstudio.terminal.startup.failure.creation_retry.count",
        "agentstudio.tcc.probe.sequence",
        "agentstudio.tcc.tccdb.path_row.count",
        "agentstudio.workspace.snapshot.pane_count",
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
        "agentstudio.bridge.header_missing",
        "agentstudio.bridge.header_supported",
        "agentstudio.ghostty.route.result",
        "agentstudio.inbox.notification.coalesced",
        "agentstudio.inbox.notification.revoked",
        "agentstudio.pane.attended",
        "agentstudio.pane.observed",
        "agentstudio.pane.pinned_to_bottom",
        "agentstudio.pane_inbox.dismissed",
        "agentstudio.preferences.global.observability_enabled",
        "agentstudio.performance.atom.cache_hit",
        "agentstudio.performance.git.has_git_internal_changes",
        "agentstudio.ghostty.surface.initial_frame_present",
        "agentstudio.ghostty.surface.startup_command_present",
        "agentstudio.full_disk_access.health.healthy",
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
        "agentstudio.startup_diagnostic.render_proof.succeeded",
        "agentstudio.tcc.bundle.changed",
        "agentstudio.tcc.bundle.executable.reachable",
        "agentstudio.tcc.tccdb.bundle_grant.present",
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
        switch key {
        case "agentstudio.bridge.plane":
            BridgeTelemetryPlane(rawValue: value) != nil
        case "agentstudio.bridge.priority":
            BridgeTelemetryPriority(rawValue: value) != nil
        case "agentstudio.bridge.slice":
            BridgeTelemetrySlice(rawValue: value) != nil
        case "agentstudio.bridge.telemetry.drop_reason":
            BridgeTelemetryDropReason(rawValue: value) != nil
        default:
            true
        }
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
