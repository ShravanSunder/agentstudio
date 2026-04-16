import Foundation

enum PaneContentClickFocusDecider {
    static func decide(
        trigger: PaneContentClickFocusTrigger,
        context: PaneFocusContext
    ) -> PaneContentClickFocusDecision {
        guard let targetTabId = context.targetTabId else {
            return PaneContentClickFocusDecision(
                selection: .keep,
                responder: .preserveCurrentResponder,
                runtime: .preserveRuntimeFocus,
                content: .preserve,
                reason: .inactivePaneRequiresSelection
            )
        }

        if context.targetPaneIsAlreadyActive {
            return PaneContentClickFocusDecision(
                selection: .keep,
                responder: .preserveCurrentResponder,
                runtime: .preserveRuntimeFocus,
                content: .preserve,
                reason: .activeContentClickPreservesOwnership
            )
        }

        switch context.targetPaneKind {
        case .terminal:
            return PaneContentClickFocusDecision(
                selection: .selectPane(tabId: targetTabId, paneId: trigger.targetPaneId),
                responder: .focusPaneHost(paneId: trigger.targetPaneId),
                runtime: .syncTerminalSurface(paneId: trigger.targetPaneId),
                content: .preserve,
                reason: .inactivePaneRequiresSelection
            )

        case .webview, .bridge, .codeViewer, .unknown:
            return PaneContentClickFocusDecision(
                selection: .selectPane(tabId: targetTabId, paneId: trigger.targetPaneId),
                responder: .preserveCurrentResponder,
                runtime: .preserveRuntimeFocus,
                content: .preserve,
                reason: .inactivePaneRequiresSelection
            )
        }
    }

}
