import Foundation

package enum AgentStudioOTLPPaneDropTaxonomy {
    package static let stringAttributeKeys: Set<String> = [
        "agentstudio.performance.tabbar.pane_drop.outcome",
        "agentstudio.performance.tabbar.pane_drop.phase",
        "agentstudio.performance.tabbar.pane_drop.reason",
    ]

    package static let numericAttributeKeys: Set<String> = [
        "agentstudio.performance.tabbar.pane_drop.frame.count"
    ]

    package static let booleanAttributeKeys: Set<String> = [
        "agentstudio.performance.tabbar.pane_drop.target_resolved"
    ]

    package static func isAllowedValue(key: String, value: String) -> Bool? {
        switch key {
        case "agentstudio.performance.tabbar.pane_drop.phase":
            return ["entered", "commit", "terminal"].contains(value)
        case "agentstudio.performance.tabbar.pane_drop.outcome":
            return ["accepted", "rejected", "requested", "ended"].contains(value)
        case "agentstudio.performance.tabbar.pane_drop.reason":
            return [
                "none", "payload_missing", "payload_decode_failed", "drawer_child",
                "management_inactive", "target_unresolved",
            ].contains(value)
        default:
            return nil
        }
    }
}
