import Foundation

enum PaneObservationResolver {
    static func isPaneCurrentlyAttended(
        paneId: UUID,
        attendedPaneId: UUID?,
        pane: (UUID) -> Pane?
    ) -> Bool {
        currentAttendedPaneId(attendedPaneId: attendedPaneId, pane: pane) == paneId
    }

    static func currentAttendedPaneId(
        attendedPaneId: UUID?,
        pane: (UUID) -> Pane?
    ) -> UUID? {
        guard let attendedPaneId else { return nil }
        if let drawer = pane(attendedPaneId)?.drawer, drawer.isExpanded {
            guard let activeChildId = drawer.activeChildId,
                !drawer.minimizedPaneIds.contains(activeChildId)
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
        pane: (UUID) -> Pane?
    ) -> Set<UUID> {
        guard let attendedPaneId else { return [] }
        let activePaneIds = currentRenderedPaneIds(activeTab: activeTab, fallbackPaneId: attendedPaneId)
        var observedPaneIds = Set<UUID>()
        for paneId in activePaneIds {
            if let drawer = pane(paneId)?.drawer, drawer.isExpanded {
                if let activeChildId = drawer.activeChildId,
                    !drawer.minimizedPaneIds.contains(activeChildId)
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
