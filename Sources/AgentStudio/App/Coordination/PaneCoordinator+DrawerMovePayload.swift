import Foundation

extension PaneCoordinator {
    func drawerMovePayloadsByParentPaneId(inTab tabId: UUID) -> [UUID: PaneDrawerMovePayload] {
        guard let tab = store.tabLayoutAtom.tab(tabId) else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: tab.allPaneIds.compactMap { paneId in
                guard let payload = drawerMovePayload(forParentPaneId: paneId, inTab: tabId) else { return nil }
                return (paneId, payload)
            }
        )
    }

    func drawerMovePayload(forParentPaneId parentPaneId: UUID, inTab tabId: UUID) -> PaneDrawerMovePayload? {
        guard let drawer = store.paneAtom.pane(parentPaneId)?.drawer else { return nil }
        guard !drawer.paneIds.isEmpty else { return nil }
        let drawerView = store.tabLayoutAtom.tab(tabId)?.arrangements
            .compactMap { $0.drawerViews[drawer.drawerId] }
            .first
        return PaneDrawerMovePayload(
            drawerId: drawer.drawerId,
            drawerPaneIds: drawer.paneIds,
            drawerView: drawerView
        )
    }
}
