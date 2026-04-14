import Foundation

enum PaneDrawerFocusDecider {
    static func decide(
        trigger: PaneDrawerFocusTrigger,
        context: PaneFocusContext
    ) -> PaneDrawerFocusDecision {
        switch trigger {
        case .selectPane(let parentPaneId, let drawerPaneId):
            return PaneDrawerFocusDecision(
                selection: .selectDrawerPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId),
                responder: .focusPaneHost(paneId: drawerPaneId),
                runtime: .preserveRuntimeFocus,
                reason: .drawerSelectionChanged
            )

        case .toggle(let parentPaneId):
            let responderPaneId =
                if context.activeDrawerParentPaneId == parentPaneId {
                    context.activeDrawerPaneId ?? parentPaneId
                } else {
                    parentPaneId
                }
            return PaneDrawerFocusDecision(
                selection: .keep,
                responder: .focusPaneHost(paneId: responderPaneId),
                runtime: .preserveRuntimeFocus,
                reason: .drawerSelectionChanged
            )
        }
    }
}
