import Testing

@testable import AgentStudioArchitectureLintCore

@Suite
struct RuleInventoryTests {
    @Test("registry preserves all expected rule ids and severities")
    func registryPreservesExpectedRules() {
        let actual = ArchitectureRuleRegistry.rules.map { rule in
            ExpectedRule(id: rule.id, severity: rule.severity)
        }

        #expect(actual.sorted() == ExpectedRuleInventory.rules.sorted())
    }
}

struct ExpectedRule: Comparable, Equatable {
    let id: String
    let severity: ArchitectureSeverity

    static func < (left: Self, right: Self) -> Bool {
        left.id < right.id
    }
}

enum ExpectedRuleInventory {
    static let rules: [ExpectedRule] = [
        ExpectedRule(id: "agentstudio_import_direction", severity: .error),
        ExpectedRule(id: "agentstudio_shared_components_are_stateless", severity: .error),
        ExpectedRule(id: "agentstudio_atomlib_is_generic", severity: .error),
        ExpectedRule(id: "agentstudio_derived_value_declared_inputs", severity: .error),
        ExpectedRule(id: "agentstudio_repo_cache_keyed_reads", severity: .error),
        ExpectedRule(id: "agentstudio_worktree_enrichment_comparator", severity: .error),
        ExpectedRule(id: "agentstudio_state_actor_path", severity: .warning),
        ExpectedRule(id: "agentstudio_ipc_programmatic_control_boundary", severity: .error),
        ExpectedRule(id: "agentstudio_appipc_port_boundary", severity: .error),
        ExpectedRule(id: "agentstudio_ipc_composition_location", severity: .error),
        ExpectedRule(id: "agentstudio_features_do_not_import_appipc", severity: .error),
        ExpectedRule(id: "agentstudio_ipc_public_surface_sanitization", severity: .error),
        ExpectedRule(id: "agentstudio_ipc_no_direct_atom_access", severity: .error),
        ExpectedRule(id: "agentstudio_no_forbidden_architecture_marker", severity: .error),
        ExpectedRule(id: "agentstudio_no_generic_clock_sleep", severity: .error),
        ExpectedRule(id: "agentstudio_no_task_sleep_in_tests", severity: .error),
        ExpectedRule(id: "agentstudio_toolbar_tooltip_source", severity: .error),
        ExpectedRule(id: "agentstudio_eventbus_subscriber_policy_required", severity: .error),
    ]
}
