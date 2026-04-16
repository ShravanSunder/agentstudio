import Foundation

enum PaneKeyboardFocusDecider {
    static func decide(
        trigger: PaneKeyboardFocusTrigger,
        context _: PaneFocusContext
    ) -> PaneKeyboardFocusDecision {
        switch trigger {
        case .moveToPane(let tabId, let paneId, let paneKind):
            return PaneKeyboardFocusDecision(
                selection: .selectPane(tabId: tabId, paneId: paneId),
                responder: responderAction(for: paneId, paneKind: paneKind),
                runtime: runtimeAction(for: paneId, paneKind: paneKind),
                keyboard: .passThrough,
                reason: .commandTriggeredFocus
            )
        }
    }

    private static func responderAction(
        for paneId: UUID,
        paneKind: PaneFocusContext.PaneKind
    ) -> PaneKeyboardResponderAction {
        switch paneKind {
        case .terminal:
            return .focusPaneHost(paneId: paneId)

        case .webview, .bridge, .codeViewer, .unknown:
            return .preserveCurrentResponder
        }
    }

    private static func runtimeAction(
        for paneId: UUID,
        paneKind: PaneFocusContext.PaneKind
    ) -> PaneKeyboardRuntimeAction {
        switch paneKind {
        case .terminal:
            return .syncTerminalSurface(paneId: paneId)

        case .webview, .bridge, .codeViewer, .unknown:
            return .preserveRuntimeFocus
        }
    }
}
