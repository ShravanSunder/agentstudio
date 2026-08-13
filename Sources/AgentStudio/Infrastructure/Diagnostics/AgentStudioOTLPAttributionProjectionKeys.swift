import Foundation

enum AgentStudioOTLPAttributionProjectionKeys {
    static let stringAttributeKeys: Set<String> = [
        "agentstudio.performance.commandbar.cache_outcome",
        "agentstudio.performance.commandbar.invalidation_reason",
        "agentstudio.performance.git.cadence_tier",
        "agentstudio.performance.git.demand_class",
        "agentstudio.performance.git.trigger_source",
    ]

    static func isAllowedValue(key: String, value: String) -> Bool? {
        switch key {
        case "agentstudio.performance.commandbar.cache_outcome":
            return ["hit", "miss"].contains(value)
        case "agentstudio.performance.commandbar.invalidation_reason":
            return [
                "scope_change", "focused_pane", "command_context", "open_generation",
                "query_meaningful_transition", "topology_observation",
            ].contains(value)
        case "agentstudio.performance.git.demand_class":
            return ["active_pane", "visible_sidebar", "explicit", "background"].contains(value)
        case "agentstudio.performance.git.trigger_source":
            return ["registration", "filesystem_change", "periodic", "visibility_change", "retry"].contains(value)
        case "agentstudio.performance.git.cadence_tier":
            return ["1", "2", "4"].contains(value)
        default:
            return nil
        }
    }
}
