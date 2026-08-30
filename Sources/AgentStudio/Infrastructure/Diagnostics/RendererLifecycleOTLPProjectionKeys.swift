enum RendererLifecycleOTLPProjectionKeys {
    static let stringAttributeKeys: Set<String> = [
        "agentstudio.startup_diagnostic.renderer_lifecycle.phase",
        "agentstudio.performance.renderer.event.kind",
        "agentstudio.performance.renderer.projection.trigger",
        "agentstudio.performance.renderer.release.reason",
        "agentstudio.performance.renderer.visibility.outcome",
    ]

    static let numericAttributeKeys: Set<String> = [
        "agentstudio.performance.renderer.active.current",
        "agentstudio.performance.renderer.close_undo.current",
        "agentstudio.performance.renderer.created.delta",
        "agentstudio.performance.renderer.created.total",
        "agentstudio.performance.renderer.free.delta",
        "agentstudio.performance.renderer.free.total",
        "agentstudio.performance.renderer.hidden.current",
        "agentstudio.performance.renderer.live.current",
        "agentstudio.performance.renderer.manager_owned.current",
        "agentstudio.performance.renderer.orphan_candidate.current",
        "agentstudio.performance.renderer.projection.changed_surface.delta",
        "agentstudio.performance.renderer.projection.changed_surface.total",
        "agentstudio.performance.renderer.projection.equal_surface.delta",
        "agentstudio.performance.renderer.projection.equal_surface.total",
        "agentstudio.performance.renderer.projection.evaluated_surface.delta",
        "agentstudio.performance.renderer.projection.evaluated_surface.total",
        "agentstudio.performance.renderer.projection.evaluation.delta",
        "agentstudio.performance.renderer.projection.evaluation.total",
        "agentstudio.performance.renderer.projection.failed_surface.delta",
        "agentstudio.performance.renderer.projection.missing_surface.delta",
        "agentstudio.performance.renderer.release.delta",
        "agentstudio.performance.renderer.release.total",
        "agentstudio.performance.renderer.sample.sequence",
        "agentstudio.performance.renderer.visibility.delivery.delta",
        "agentstudio.performance.renderer.visibility.delivery.total",
        "agentstudio.performance.renderer.visibility.equal_suppressed.delta",
        "agentstudio.performance.renderer.visibility.equal_suppressed.total",
    ]

    static let booleanAttributeKeys: Set<String> = [
        "agentstudio.performance.renderer.lifecycle.valid",
        "agentstudio.performance.renderer.visibility.requested_visible",
    ]

    static func isAllowedStringValue(key: String, value: String) -> Bool? {
        switch key {
        case "agentstudio.startup_diagnostic.renderer_lifecycle.phase":
            return ["initial", "restart", "soak"].contains(value)
        case "agentstudio.performance.renderer.event.kind":
            return [
                "created", "manager_population", "permanent_release", "deinitialized_free",
                "visibility_delivery", "projection_evaluation",
            ].contains(value)
        case "agentstudio.performance.renderer.release.reason":
            return [
                "repair_replacement", "explicit_termination", "explicit_removal", "undo_expired",
                "creation_rollback",
            ].contains(value)
        case "agentstudio.performance.renderer.visibility.outcome":
            return RendererVisibilityDeliveryOutcome(rawValue: value) != nil
        case "agentstudio.performance.renderer.projection.trigger":
            return RendererVisibilityProjectionTrigger(rawValue: value) != nil
        default:
            return nil
        }
    }
}
