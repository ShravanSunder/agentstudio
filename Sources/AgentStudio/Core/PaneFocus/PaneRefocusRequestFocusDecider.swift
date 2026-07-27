import Foundation

enum PaneRefocusRequestFocusDecider {
    static func decide(
        trigger _: PaneRefocusRequestTrigger,
        context: PaneFocusContext
    ) -> PaneRefocusRequestDecision {
        guard let targetPaneId = context.activePaneId else {
            return PaneRefocusRequestDecision(
                responder: .preserveCurrentResponder,
                runtime: .preserveRuntimeFocus,
                reason: .explicitRefocus
            )
        }

        switch context.targetPaneKind {
        case .terminal:
            return PaneRefocusRequestDecision(
                responder: .focusPaneHost(paneId: targetPaneId),
                runtime: .syncTerminalSurface(paneId: targetPaneId),
                reason: .explicitRefocus
            )

        case .webview, .bridge, .codeViewer:
            return PaneRefocusRequestDecision(
                responder: nonTerminalResponderAction(for: targetPaneId, mountedContent: context.targetMountedContent),
                runtime: .preserveRuntimeFocus,
                reason: .explicitRefocus
            )

        case .unknown:
            return PaneRefocusRequestDecision(
                responder: .preserveCurrentResponder,
                runtime: .preserveRuntimeFocus,
                reason: .explicitRefocus
            )
        }
    }

    private static func nonTerminalResponderAction(
        for paneId: UUID,
        mountedContent: PaneFocusContext.MountedContentState
    ) -> PaneRefocusRequestResponderAction {
        switch mountedContent {
        case .nonTerminal(let acceptsFirstResponder):
            return acceptsFirstResponder ? .focusMountedContent(paneId: paneId) : .focusPaneHost(paneId: paneId)

        case .terminal:
            return .focusPaneHost(paneId: paneId)

        case .unmounted:
            return .focusPaneHost(paneId: paneId)
        }
    }
}
