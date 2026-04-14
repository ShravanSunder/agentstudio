import Foundation

enum PaneCommandFocusDecider {
    static func decide(
        trigger: PaneCommandFocusTrigger,
        context: PaneFocusContext
    ) -> PaneCommandFocusDecision {
        switch trigger {
        case .focusPane(let tabId, let paneId):
            return PaneCommandFocusDecision(
                selection: .selectPane(tabId: tabId, paneId: paneId),
                responder: responderAction(for: paneId, paneKind: context.targetPaneKind),
                runtime: runtimeAction(for: paneId, paneKind: context.targetPaneKind),
                reason: .commandTriggeredFocus
            )

        case .selectTab(let tabId):
            return PaneCommandFocusDecision(
                selection: .selectTab(tabId),
                responder: .preserveCurrentResponder,
                runtime: .preserveRuntimeFocus,
                reason: .commandTriggeredFocus
            )

        case .paneCreated(let paneId, let paneKind):
            return PaneCommandFocusDecision(
                selection: .keep,
                responder: responderAction(for: paneId, paneKind: paneKind),
                runtime: runtimeAction(for: paneId, paneKind: paneKind),
                reason: .commandTriggeredFocus
            )
        }
    }

    private static func responderAction(
        for paneId: UUID,
        paneKind: PaneFocusContext.PaneKind
    ) -> PaneCommandResponderAction {
        switch paneKind {
        case .terminal, .webview, .bridge, .codeViewer:
            return .focusPaneHost(paneId: paneId)

        case .unknown:
            return .preserveCurrentResponder
        }
    }

    private static func runtimeAction(
        for paneId: UUID,
        paneKind: PaneFocusContext.PaneKind
    ) -> PaneCommandRuntimeAction {
        switch paneKind {
        case .terminal:
            return .syncTerminalSurface(paneId: paneId)

        case .webview, .bridge, .codeViewer, .unknown:
            return .preserveRuntimeFocus
        }
    }
}
