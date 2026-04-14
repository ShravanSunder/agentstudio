import Foundation

enum PaneModeFocusDecider {
    static func decide(
        trigger: PaneModeFocusTrigger,
        context: PaneFocusContext
    ) -> PaneModeFocusDecision {
        switch trigger.transition {
        case .enteredManagementMode:
            return PaneModeFocusDecision(
                responder: enteredManagementModeResponderAction(context: context),
                keyboard: .consume,
                content: .block,
                reason: .managementModeEntered
            )

        case .exitedManagementMode:
            return PaneModeFocusDecision(
                responder: .preserveCurrentResponder,
                keyboard: .passThrough,
                content: .release,
                reason: .explicitRefocus
            )
        }
    }

    private static func enteredManagementModeResponderAction(
        context: PaneFocusContext
    ) -> PaneModeResponderAction {
        switch context.targetPaneKind {
        case .terminal:
            return .clearToWindowContent

        case .webview, .bridge, .codeViewer, .unknown:
            return .preserveCurrentResponder
        }
    }
}
