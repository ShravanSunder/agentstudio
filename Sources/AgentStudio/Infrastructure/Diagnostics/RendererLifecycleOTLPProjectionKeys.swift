/// Allowlist for `performance.renderer.lifecycle` attributes exported through
/// `AgentStudioOTLPTraceProjection`. Deliberately excludes any surface/pane identity, title, or
/// path — the event contract forbids exporting them, and this file is the enforcement point.
package enum RendererLifecycleOTLPProjectionKeys {
    package static let stringAttributeKeys: Set<String> = [
        "agentstudio.performance.renderer.event.kind"
    ]

    package static let numericAttributeKeys: Set<String> = [
        "agentstudio.performance.renderer.created.total",
        "agentstudio.performance.renderer.released.total",
        "agentstudio.performance.renderer.freed.total",
        "agentstudio.performance.renderer.active.current",
        "agentstudio.performance.renderer.hidden.current",
        "agentstudio.performance.renderer.close_undo.current",
        "agentstudio.performance.renderer.live.current",
        "agentstudio.performance.renderer.manager_owned.current",
        "agentstudio.performance.renderer.orphan_candidate.current",
        "agentstudio.performance.renderer.sample.sequence",
        "agentstudio.performance.renderer.created.delta",
        "agentstudio.performance.renderer.released.delta",
        "agentstudio.performance.renderer.freed.delta",
        "agentstudio.performance.renderer.reconcile.applied",
        "agentstudio.performance.renderer.reconcile.equal",
        "agentstudio.performance.renderer.reconcile.missing",
        "agentstudio.performance.renderer.reconcile.equal_since_last_emit",
    ]

    package static let booleanAttributeKeys: Set<String> = [
        "agentstudio.performance.renderer.lifecycle.valid",
        "agentstudio.performance.renderer.window.visible",
        "agentstudio.performance.renderer.window.miniaturized",
        "agentstudio.performance.renderer.window.occluded",
    ]

    package static func isAllowedStringValue(key: String, value: String) -> Bool? {
        guard key == "agentstudio.performance.renderer.event.kind" else { return nil }
        return RendererLifecycleAction(rawValue: value) != nil
    }
}
