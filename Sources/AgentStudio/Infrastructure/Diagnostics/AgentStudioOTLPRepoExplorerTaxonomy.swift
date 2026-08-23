import Foundation

enum AgentStudioOTLPRepoExplorerTaxonomy {
    static let controlledIdentifierAttributeKeys: Set<String> = [
        "agentstudio.performance.repo_explorer.native_table_pilot.policy_id",
        "agentstudio.startup_diagnostic.native_table_pilot.policy_id",
        "agentstudio.startup_diagnostic.sidebar_proof.policy_id",
    ]

    static let numericAttributeKeys: Set<String> = [
        "agentstudio.startup_diagnostic.sidebar_proof.policy_version",
        "agentstudio.startup_diagnostic.sidebar_proof.idle_p99_max_percent",
        "agentstudio.startup_diagnostic.sidebar_proof.action_p95_max_percent",
        "agentstudio.startup_diagnostic.sidebar_proof.sample_interval_ms",
        "agentstudio.startup_diagnostic.sidebar_proof.idle_sample_floor",
        "agentstudio.startup_diagnostic.sidebar_proof.action_count_floor",
        "agentstudio.startup_diagnostic.sidebar_proof.action_sample_floor",
        "agentstudio.startup_diagnostic.sidebar_proof.search_character_count",
        "agentstudio.startup_diagnostic.sidebar_proof.search_character_interval_ms",
        "agentstudio.startup_diagnostic.sidebar_proof.quiescence_interval_ms",
        "agentstudio.startup_diagnostic.sidebar_proof.readback_timeout_ms",
        "agentstudio.startup_diagnostic.sidebar_proof.sampler_gap_max_ms",
        "agentstudio.startup_diagnostic.sidebar_proof.unrelated_host_cpu_max_percent",
        "agentstudio.startup_diagnostic.sidebar_proof.diagnostic_cpu_delta_max_points",
        "agentstudio.startup_diagnostic.sidebar_proof.diagnostic_interaction_growth_max_percent",
        "agentstudio.performance.sidebar.readback.semantic_generation",
        "agentstudio.performance.sidebar.readback.acknowledged_revision",
        "agentstudio.performance.sidebar.readback.visible_generation",
        "agentstudio.performance.sidebar.readback.represented_row_count",
        "agentstudio.performance.sidebar.proof.action.sequence",
        "agentstudio.performance.sidebar.proof.monotonic_ns",
        "agentstudio.performance.repo_explorer.native_table_pilot.baseline_measurement.count",
        "agentstudio.performance.repo_explorer.native_table_pilot.baseline_p95_ms",
        "agentstudio.performance.repo_explorer.native_table_pilot.completed",
        "agentstudio.performance.repo_explorer.native_table_pilot.drain_completed.count",
        "agentstudio.performance.repo_explorer.native_table_pilot.doubled_measurement.count",
        "agentstudio.performance.repo_explorer.native_table_pilot.doubled_p95_ms",
        "agentstudio.performance.repo_explorer.native_table_pilot.exactness",
        "agentstudio.performance.repo_explorer.native_table_pilot.growth_percent",
        "agentstudio.performance.repo_explorer.native_table_pilot.liveness_projection.count",
        "agentstudio.performance.repo_explorer.native_table_pilot.measured.count",
        "agentstudio.performance.repo_explorer.native_table_pilot.membership_p95_ms",
        "agentstudio.performance.repo_explorer.native_table_pilot.passed",
        "agentstudio.performance.repo_explorer.native_table_pilot.policy_version",
        "agentstudio.performance.repo_explorer.native_table_pilot.result_version",
        "agentstudio.performance.repo_explorer.native_table_pilot.template_pair.count",
        "agentstudio.performance.repo_explorer.native_table_pilot.warmup.count",
        "agentstudio.startup_diagnostic.native_table_pilot.baseline_measurement.count",
        "agentstudio.startup_diagnostic.native_table_pilot.baseline_p95_ms",
        "agentstudio.startup_diagnostic.native_table_pilot.completed",
        "agentstudio.startup_diagnostic.native_table_pilot.drain_completed.count",
        "agentstudio.startup_diagnostic.native_table_pilot.doubled_measurement.count",
        "agentstudio.startup_diagnostic.native_table_pilot.doubled_p95_ms",
        "agentstudio.startup_diagnostic.native_table_pilot.exactness",
        "agentstudio.startup_diagnostic.native_table_pilot.growth_percent",
        "agentstudio.startup_diagnostic.native_table_pilot.liveness_projection.count",
        "agentstudio.startup_diagnostic.native_table_pilot.measured_transaction.count",
        "agentstudio.startup_diagnostic.native_table_pilot.passed",
        "agentstudio.startup_diagnostic.native_table_pilot.policy_version",
        "agentstudio.startup_diagnostic.native_table_pilot.result_version",
        "agentstudio.startup_diagnostic.native_table_pilot.scale.count",
        "agentstudio.startup_diagnostic.native_table_pilot.template_pair.count",
        "agentstudio.startup_diagnostic.native_table_pilot.warmup_transaction.count",
        "agentstudio.performance.forge.input.automatic.count",
        "agentstudio.performance.forge.input.manual.count",
        "agentstudio.performance.forge.input.follow_up.count",
        "agentstudio.performance.forge.admission.admitted.count",
        "agentstudio.performance.forge.admission.no_demand_rejected.count",
        "agentstudio.performance.forge.admission.missing_origin_rejected.count",
        "agentstudio.performance.forge.admission.active_request_coalesced.count",
        "agentstudio.performance.forge.admission.capacity_limited.count",
        "agentstudio.performance.forge.admission.freshness_deferred.count",
        "agentstudio.performance.forge.admission.backoff_deferred.count",
        "agentstudio.performance.forge.execution.started.count",
        "agentstudio.performance.forge.execution.completed.count",
        "agentstudio.performance.forge.execution.failed.count",
        "agentstudio.performance.forge.execution.cancelled.count",
        "agentstudio.performance.forge.execution.superseded.count",
        "agentstudio.performance.forge.validation.current.count",
        "agentstudio.performance.forge.validation.stale_generation.count",
        "agentstudio.performance.forge.validation.stale_origin.count",
        "agentstudio.performance.forge.validation.stale_scope.count",
        "agentstudio.performance.forge.publication.published.count",
        "agentstudio.performance.forge.publication.equal.count",
        "agentstudio.performance.forge.publication.invalidated.count",
        "agentstudio.performance.forge.deadline.scheduled.count",
        "agentstudio.performance.forge.deadline.rescheduled.count",
        "agentstudio.performance.forge.deadline.fired.count",
        "agentstudio.performance.forge.deadline.cancelled.count",
    ]

    static let stringAttributeKeys: Set<String> = [
        "agentstudio.startup_diagnostic.sidebar_proof.policy_id",
        "agentstudio.performance.sidebar.readback.grouping_mode",
        "agentstudio.performance.sidebar.readback.query_state",
        "agentstudio.performance.sidebar.readback.demand_state",
        "agentstudio.performance.sidebar.readback.presentation_state",
        "agentstudio.performance.sidebar.readback.focus_disposition",
        "agentstudio.performance.sidebar.readback.accessibility_disposition",
        "agentstudio.performance.sidebar.proof.population",
        "agentstudio.startup_diagnostic.sidebar_proof.standard_trace_tags",
        "agentstudio.startup_diagnostic.sidebar_proof.diagnostic_trace_tags",
        "agentstudio.startup_diagnostic.sidebar_proof.idle_populations",
        "agentstudio.startup_diagnostic.sidebar_proof.action_populations",
        "agentstudio.performance.repo_explorer.native_table_pilot.failure_reason",
        "agentstudio.performance.repo_explorer.native_table_pilot.outcome",
        "agentstudio.performance.repo_explorer.native_table_pilot.policy_id",
        "agentstudio.performance.repo_explorer.native_table_pilot.scale",
        "agentstudio.startup_diagnostic.native_table_pilot.failure_reason",
        "agentstudio.startup_diagnostic.native_table_pilot.policy_id",
        "agentstudio.performance.repo_explorer.facet",
        "agentstudio.performance.repo_explorer.key_class",
        "agentstudio.performance.repo_explorer.outcome",
        "agentstudio.performance.repo_explorer.row_relation",
        "agentstudio.performance.repo_explorer.stage",
        "agentstudio.performance.repo_explorer.outline_apply_proxy.outcome",
        "agentstudio.performance.repo_explorer.row_body_evaluation.outcome",
        "agentstudio.performance.repo_explorer.row_kind",
        "agentstudio.performance.repo_explorer.scroll_frame_gap.outcome",
        "agentstudio.performance.repo_explorer.surface",
        "agentstudio.performance.repo_explorer.visible_row_count_bucket",
        "agentstudio.performance.filesystem.stage",
        "agentstudio.performance.filesystem.outcome",
        "agentstudio.performance.forge.stage",
        "agentstudio.performance.forge.outcome",
    ]

    static let structuredStringAttributeKeys: Set<String> = [
        "agentstudio.startup_diagnostic.sidebar_proof.standard_trace_tags",
        "agentstudio.startup_diagnostic.sidebar_proof.diagnostic_trace_tags",
        "agentstudio.startup_diagnostic.sidebar_proof.idle_populations",
        "agentstudio.startup_diagnostic.sidebar_proof.action_populations",
    ]

    static func isAllowedValue(key: String, value: String) -> Bool? {
        if let result = isAllowedSidebarProofValue(key: key, value: value) {
            return result
        }
        return switch key {
        case "agentstudio.startup_diagnostic.native_table_pilot.failure_reason":
            [
                "none", "completion_timeout", "fixture_invalid", "transaction_invalid",
                "measurement_count_mismatch", "membership_p95_exceeded", "doubled_growth_exceeded",
            ].contains(value)
        case "agentstudio.startup_diagnostic.native_table_pilot.policy_id":
            value == "sidebar-native-table-pilot"
        case "agentstudio.performance.repo_explorer.native_table_pilot.failure_reason":
            [
                "none", "completion_timeout", "fixture_invalid", "transaction_invalid",
                "measurement_count_mismatch", "membership_p95_exceeded", "doubled_growth_exceeded",
            ].contains(value)
        case "agentstudio.performance.repo_explorer.native_table_pilot.outcome":
            ["completed", "passed", "failed"].contains(value)
        case "agentstudio.performance.repo_explorer.native_table_pilot.policy_id":
            value == "sidebar-native-table-pilot"
        case "agentstudio.performance.repo_explorer.native_table_pilot.scale":
            ["baseline", "doubled", "summary"].contains(value)
        case "agentstudio.performance.repo_explorer.stage":
            [
                "observe_project", "distinct", "coalesce", "admission", "execute", "validate", "publish",
                "materialize", "deadline",
                "eager_admission", "projection_worker", "command_affected_row", "command_whole_surface",
                "capture_rebuild", "affected_row", "membership_path", "whole_surface", "mainactor_apply",
                "final_projection", "atom_slot", "other",
            ].contains(value)
        case "agentstudio.performance.repo_explorer.key_class":
            [
                "ordinary_run", "rendered_repo_favorite", "rendered_worktree_fact", "relevant",
                "unrelated_tab_arrangement_pane", "observed_tab_title", "unrendered_attendance",
                "missing_declared_key", "diagnostic_settle",
            ].contains(value)
        case "agentstudio.performance.repo_explorer.outcome":
            [
                "observed", "suppressed", "coalesced", "admitted", "executed", "published", "materialized",
                "equal", "changed", "unknown", "retained", "replaced", "deferred", "rejected",
                "capacity_limited", "started", "completed", "current", "cancelled", "superseded", "stale",
                "stale_generation", "stale_origin", "stale_scope", "failed", "invalidated", "revoked",
                "scheduled", "rescheduled", "fired", "relevant_key", "reference_equal",
                "reference_different", "other",
            ].contains(value)
        case "agentstudio.performance.repo_explorer.facet":
            ["attendance", "unread"].contains(value)
        case "agentstudio.performance.repo_explorer.row_relation":
            ["owning", "unrendered", "affected_row"].contains(value)
        case "agentstudio.performance.repo_explorer.row_body_evaluation.outcome":
            ["success", "failed", "incomplete"].contains(value)
        case "agentstudio.performance.repo_explorer.row_kind":
            [
                "section_header", "loading_section_header", "loading_repo", "resolved_group_header",
                "resolved_worktree", "resolved_pane", "topology_fault",
            ].contains(value)
        case "agentstudio.performance.repo_explorer.scroll_frame_gap.outcome":
            ["sampled", "incomplete"].contains(value)
        case "agentstudio.performance.repo_explorer.surface":
            value == "repo"
        case "agentstudio.performance.repo_explorer.visible_row_count_bucket":
            ["zero", "1_8", "9_16", "17_32", "33_plus"].contains(value)
        case "agentstudio.performance.filesystem.stage":
            ["affected_key_apply", "coarse_refresh_debt"].contains(value)
        case "agentstudio.performance.filesystem.outcome":
            ["applied", "rejected", "overflow_coarse"].contains(value)
        case "agentstudio.performance.forge.stage":
            ["follow_up", "facts_publication"].contains(value)
        case "agentstudio.performance.forge.outcome":
            ["admitted", "deferred", "equal"].contains(value)
        default:
            nil
        }
    }

    private static func isAllowedSidebarProofValue(key: String, value: String) -> Bool? {
        switch key {
        case "agentstudio.startup_diagnostic.sidebar_proof.policy_id":
            value == "strict-sidebar-cpu"
        case "agentstudio.startup_diagnostic.sidebar_proof.standard_trace_tags":
            value == "performance,app.startup,terminal.startup"
        case "agentstudio.startup_diagnostic.sidebar_proof.diagnostic_trace_tags":
            value == "performance,atoms,app.startup,terminal.startup"
        case "agentstudio.startup_diagnostic.sidebar_proof.idle_populations":
            value == "zero_pty_idle,quiescent_pty_idle"
        case "agentstudio.startup_diagnostic.sidebar_proof.action_populations":
            value == "search_clear,grouping,hide_show,tab_switch"
        case "agentstudio.performance.sidebar.proof.population":
            ["zero_pty_idle", "quiescent_pty_idle", "search_clear", "grouping", "hide_show", "tab_switch"]
                .contains(value)
        case "agentstudio.performance.sidebar.readback.grouping_mode":
            ["repo", "pane", "tab"].contains(value)
        case "agentstudio.performance.sidebar.readback.query_state":
            ["empty", "non_empty"].contains(value)
        case "agentstudio.performance.sidebar.readback.demand_state":
            ["demanded", "hidden"].contains(value)
        case "agentstudio.performance.sidebar.readback.presentation_state",
            "agentstudio.performance.sidebar.readback.accessibility_disposition":
            ["ready", "unavailable"].contains(value)
        case "agentstudio.performance.sidebar.readback.focus_disposition":
            ["filter_focused", "not_focused"].contains(value)
        default:
            nil
        }
    }
}
