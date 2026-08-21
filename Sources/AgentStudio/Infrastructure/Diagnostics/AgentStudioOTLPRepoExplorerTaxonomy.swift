import Foundation

enum AgentStudioOTLPRepoExplorerTaxonomy {
    static let numericAttributeKeys: Set<String> = [
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

    static func isAllowedValue(key: String, value: String) -> Bool? {
        switch key {
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
}
