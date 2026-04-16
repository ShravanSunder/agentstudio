import Foundation

enum PaneModeFocusDecider {
    static func decide(
        trigger: PaneModeFocusTrigger,
        context: PaneFocusContext
    ) -> PaneModeFocusDecision {
        switch trigger.transition {
        case .enteredManagementLayer:
            return PaneModeFocusDecision(
                responder: enteredManagementLayerResponderAction(context: context),
                keyboard: .consume,
                content: .block,
                reason: .managementLayerEntered
            )

        case .exitedManagementLayer:
            return PaneModeFocusDecision(
                responder: .preserveCurrentResponder,
                keyboard: .passThrough,
                content: .release,
                reason: .explicitRefocus
            )
        }
    }

    private static func enteredManagementLayerResponderAction(
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
