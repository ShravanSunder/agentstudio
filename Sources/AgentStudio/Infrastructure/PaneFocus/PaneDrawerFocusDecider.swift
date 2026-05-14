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
            let responder: PaneDrawerResponderAction
            if context.activeDrawer?.parentPaneId == parentPaneId {
                if let drawerPaneId = context.activeDrawer?.paneId {
                    responder = .focusPaneHost(paneId: drawerPaneId)
                } else if context.activeDrawer?.isEmpty == true {
                    responder = .preserveCurrentResponder
                } else {
                    responder = .focusPaneHost(paneId: parentPaneId)
                }
            } else {
                responder = .focusPaneHost(paneId: parentPaneId)
            }
            return PaneDrawerFocusDecision(
                selection: .keep,
                responder: responder,
                runtime: .preserveRuntimeFocus,
                reason: .drawerSelectionChanged
            )
        }
    }
}
