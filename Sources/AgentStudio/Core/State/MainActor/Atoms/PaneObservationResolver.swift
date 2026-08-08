import Foundation

package enum PaneObservationResolver {
    package static func isPaneCurrentlyAttended(
        paneId: UUID,
        attendedPaneId: UUID?,
        pane: (UUID) -> Pane?,
        drawerView: (UUID) -> DrawerView? = { _ in nil }
    ) -> Bool {
        currentAttendedPaneId(attendedPaneId: attendedPaneId, pane: pane, drawerView: drawerView) == paneId
    }

    package static func currentAttendedPaneId(
        attendedPaneId: UUID?,
        pane: (UUID) -> Pane?,
        drawerView: (UUID) -> DrawerView? = { _ in nil }
    ) -> UUID? {
        currentAttendedPaneId(
            attendedPaneId: attendedPaneId,
            isDrawerExpanded: { pane($0)?.drawer?.isExpanded == true },
            drawerView: drawerView
        )
    }

    package static func currentAttendedPaneId(
        attendedPaneId: UUID?,
        isDrawerExpanded: (UUID) -> Bool,
        drawerView: (UUID) -> DrawerView? = { _ in nil }
    ) -> UUID? {
        guard let attendedPaneId else { return nil }
        if isDrawerExpanded(attendedPaneId) {
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

    package static func currentObservedPaneIds(
        attendedPaneId: UUID?,
        activeTab: Tab?,
        zoomSourcePaneId: UUID? = nil,
        pane: (UUID) -> Pane?,
        drawerView: (UUID) -> DrawerView? = { _ in nil }
    ) -> Set<UUID> {
        currentObservedPaneIds(
            attendedPaneId: attendedPaneId,
            activeTab: activeTab,
            zoomSourcePaneId: zoomSourcePaneId,
            isDrawerExpanded: { pane($0)?.drawer?.isExpanded == true },
            drawerView: drawerView
        )
    }

    package static func currentObservedPaneIds(
        attendedPaneId: UUID?,
        activeTab: Tab?,
        zoomSourcePaneId: UUID? = nil,
        isDrawerExpanded: (UUID) -> Bool,
        drawerView: (UUID) -> DrawerView? = { _ in nil }
    ) -> Set<UUID> {
        guard let attendedPaneId else { return [] }
        let activePaneIds = currentRenderedPaneIds(
            activeTab: activeTab,
            zoomSourcePaneId: zoomSourcePaneId,
            fallbackPaneId: attendedPaneId
        )
        var observedPaneIds = Set<UUID>()
        for paneId in activePaneIds {
            if isDrawerExpanded(paneId) {
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

    package static func currentRenderedPaneIds(
        activeTab: Tab?,
        zoomSourcePaneId: UUID? = nil,
        fallbackPaneId: UUID
    ) -> [UUID] {
        guard let activeTab else { return [fallbackPaneId] }
        if let zoomSourcePaneId {
            return [zoomSourcePaneId]
        }
        return activeTab.activePaneIds.filter { !activeTab.activeMinimizedPaneIds.contains($0) }
    }
}
