import Foundation

enum DragAutoDismissDecision {
    static func shouldAutoDismiss(
        payload: PaneDragPayload,
        destinationTabId: UUID,
        destinationExpandedDrawerParentPaneId: UUID?
    ) -> UUID? {
        guard payload.drawerParentPaneId == nil else { return nil }
        guard let drawerParentPaneId = destinationExpandedDrawerParentPaneId else { return nil }
        guard destinationTabId != payload.tabId else { return nil }
        return drawerParentPaneId
    }
}
