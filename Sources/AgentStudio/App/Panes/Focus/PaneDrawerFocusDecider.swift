import Foundation

enum PaneDrawerFocusDecider {
    static func decide(
        trigger: PaneDrawerFocusTrigger,
        context _: PaneFocusContext
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
            return PaneDrawerFocusDecision(
                selection: .keep,
                responder: .focusPaneHost(paneId: parentPaneId),
                runtime: .preserveRuntimeFocus,
                reason: .drawerSelectionChanged
            )
        }
    }
}
