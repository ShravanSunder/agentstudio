import Foundation

struct AgentStudioOTLPProjectedLogRecord: Equatable, Sendable {
    let timeUnixNano: UInt64
    let severityText: AgentStudioTraceSeverity
    let body: String
    let traceID: String?
    let spanID: String?
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
            traceID: nil,
            spanID: nil,
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
        "agentstudio.command.source",
        "agentstudio.envelope.scope",
        "agentstudio.eventbus.consumer",
        "agentstudio.eventbus.name",
        "agentstudio.pane.kind",
        "agentstudio.performance.coordinator.phase",
        "agentstudio.performance.atom.kind",
        "agentstudio.performance.atom.operation",
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
        "agentstudio.terminal.startup.outcome",
        "agentstudio.terminal.startup.phase",
        "agentstudio.trace.tag",
        "agentstudio.workspace.boot.step",
        "agentstudio.zmx.startup.inventory_outcome",
        "dev.runtime.flavor",
        "dev.branch.name",
    ]

    private static let allowedNumericAttributeKeys: Set<String> = [
        "agentstudio.display.count",
        "agentstudio.envelope.schema_version",
        "agentstudio.envelope.seq",
        "agentstudio.ghostty.status",
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
        "agentstudio.performance.git.dropped_subscriber.count",
        "agentstudio.performance.git.enqueued.count",
        "agentstudio.performance.git.event_posted.count",
        "agentstudio.performance.git.input_path.count",
        "agentstudio.performance.git.pending.count",
        "agentstudio.performance.git.registered.count",
        "agentstudio.performance.git.running.count",
        "agentstudio.performance.git.snapshot_dedup.count",
        "agentstudio.performance.git.status.duration_ms",
        "agentstudio.performance.git.status.elapsed_ms",
        "agentstudio.performance.git.suppressed_git_internal_path.count",
        "agentstudio.performance.git.suppressed_ignored_path.count",
        "agentstudio.performance.git.tick.count",
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
        "agentstudio.workspace.snapshot.pane_count",
        "agentstudio.zmx.startup.hydrated_anchor_count",
        "agentstudio.zmx.startup.live_session_count",
        "agentstudio.zmx.startup.protected_session_count",
        "agentstudio.zmx.startup.unmatched_live_session_count",
        "agentstudio.zmx.startup.unresolved_candidate_count",
        "agentstudio.zmx.socket_path_headroom",
    ]

    private static let allowedBooleanAttributeKeys: Set<String> = [
        "agentstudio.app.is_active",
        "agentstudio.performance.atom.cache_hit",
        "agentstudio.performance.git.has_git_internal_changes",
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
        "agentstudio.workspace.snapshot.has_tab_membership_mismatch",
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
                isSafeControlledString(stringValue)
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
}
