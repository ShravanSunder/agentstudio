import Foundation

enum PaneObservationResolver {
    static func isPaneCurrentlyAttended(
        paneId: UUID,
        attendedPaneId: UUID?,
        pane: (UUID) -> Pane?,
        drawerView: (UUID) -> DrawerView? = { _ in nil }
    ) -> Bool {
        currentAttendedPaneId(attendedPaneId: attendedPaneId, pane: pane, drawerView: drawerView) == paneId
    }

    static func currentAttendedPaneId(
        attendedPaneId: UUID?,
        pane: (UUID) -> Pane?,
        drawerView: (UUID) -> DrawerView? = { _ in nil }
    ) -> UUID? {
        guard let attendedPaneId else { return nil }
        if let drawer = pane(attendedPaneId)?.drawer, drawer.isExpanded {
            guard let view = drawerView(attendedPaneId),
                let activeChildId = view.activeChildId,
                !view.minimizedPaneIds.contains(activeChildId)
            else {
                return nil
            }
            return activeChildId
        }
        return attendedPaneId
    }

    static func currentObservedPaneIds(
        attendedPaneId: UUID?,
        activeTab: Tab?,
        pane: (UUID) -> Pane?,
        drawerView: (UUID) -> DrawerView? = { _ in nil }
    ) -> Set<UUID> {
        guard let attendedPaneId else { return [] }
        let activePaneIds = currentRenderedPaneIds(activeTab: activeTab, fallbackPaneId: attendedPaneId)
        var observedPaneIds = Set<UUID>()
        for paneId in activePaneIds {
            if let drawer = pane(paneId)?.drawer, drawer.isExpanded {
                if let view = drawerView(paneId),
                    let activeChildId = view.activeChildId,
                    !view.minimizedPaneIds.contains(activeChildId)
                {
                    observedPaneIds.insert(activeChildId)
                }
            } else {
                observedPaneIds.insert(paneId)
            }
        }
        return observedPaneIds
    }

    static func currentRenderedPaneIds(activeTab: Tab?, fallbackPaneId: UUID) -> [UUID] {
        guard let activeTab else { return [fallbackPaneId] }
        if let zoomedPaneId = activeTab.zoomedPaneId {
            return [zoomedPaneId]
        }
        return activeTab.activePaneIds.filter { !activeTab.activeMinimizedPaneIds.contains($0) }
    }
}
