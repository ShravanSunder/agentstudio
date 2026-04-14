import Foundation

enum PaneTabClickFocusDecider {
    static func decide(
        trigger: PaneTabClickFocusTrigger,
        context _: PaneFocusContext
    ) -> PaneTabClickFocusDecision {
        PaneTabClickFocusDecision(
            selection: .selectTab(trigger.targetTabId),
            responder: .preserveCurrentResponder,
            runtime: .preserveRuntimeFocus,
            reason: .inactivePaneRequiresSelection
        )
    }
}
