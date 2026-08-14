import Foundation

enum PaneRefocusRequestFocusDecider {
    static func decide(
        trigger: PaneRefocusRequestTrigger,
        context: PaneFocusContext
    ) -> PaneRefocusRequestDecision {
        guard let targetPaneId = context.activePaneId else {
            return PaneRefocusRequestDecision(
                responder: .preserveCurrentResponder,
                runtime: .preserveRuntimeFocus,
                reason: .explicitRefocus
            )
        }

        let shouldPreserveUserOwnedResponder =
            (trigger.reason == .restoreTail || trigger.reason == .parkedRestoreReplay)
            && context.currentResponderOwnership == .userOwned

        switch context.targetPaneKind {
        case .terminal:
            return PaneRefocusRequestDecision(
                responder: shouldPreserveUserOwnedResponder
                    ? .preserveCurrentResponder
                    : .focusPaneHost(paneId: targetPaneId),
                runtime: shouldPreserveUserOwnedResponder
                    ? .preserveRuntimeFocus
                    : .syncTerminalSurface(paneId: targetPaneId),
                reason: .explicitRefocus
            )

        case .webview, .bridge, .codeViewer:
            return PaneRefocusRequestDecision(
                responder: shouldPreserveUserOwnedResponder
                    ? .preserveCurrentResponder
                    : nonTerminalResponderAction(
                        for: targetPaneId,
                        mountedContent: context.targetMountedContent
                    ),
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
