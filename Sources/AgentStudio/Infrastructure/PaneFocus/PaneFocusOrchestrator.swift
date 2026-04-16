import Foundation

enum PaneFocusOrchestrator {
    static func decide(
        trigger: PaneFocusTrigger,
        context: PaneFocusContext
    ) -> PaneFocusDecision {
        switch trigger {
        case .contentClick(let trigger):
            return .contentClick(
                PaneContentClickFocusDecider.decide(trigger: trigger, context: context)
            )
        case .tabClick(let trigger):
            return .tabClick(
                PaneTabClickFocusDecider.decide(trigger: trigger, context: context)
            )
        case .drawer(let trigger):
            return .drawer(
                PaneDrawerFocusDecider.decide(trigger: trigger, context: context)
            )
        case .keyboard(let trigger):
            return .keyboard(
                PaneKeyboardFocusDecider.decide(trigger: trigger, context: context)
            )
        case .mode(let trigger):
            return .mode(
                PaneModeFocusDecider.decide(trigger: trigger, context: context)
            )
        case .refocusRequest(let trigger):
            return .refocusRequest(
                PaneRefocusRequestFocusDecider.decide(trigger: trigger, context: context)
            )
        case .command(let trigger):
            return .command(
                PaneCommandFocusDecider.decide(trigger: trigger, context: context)
            )
        }
    }
}
