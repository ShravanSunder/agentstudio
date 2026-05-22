import Foundation

enum TabArrangementRepairRules {
    static func removingPane(
        _ paneId: UUID,
        removingDrawerIds drawerIds: Set<UUID> = [],
        from arrangements: [PaneArrangement]
    ) -> [PaneArrangement] {
        arrangements.map { arrangement in
            var updated = arrangement
            for drawerId in drawerIds {
                updated.drawerViews.removeValue(forKey: drawerId)
            }
            for drawerId in updated.drawerViews.keys {
                guard var drawerView = updated.drawerViews[drawerId] else { continue }
                drawerView.minimizedPaneIds.remove(paneId)
                if drawerView.layout.contains(paneId) {
                    drawerView.layout =
                        drawerView.layout.removing(paneId: paneId, sizingMode: .proportional)
                        ?? DrawerGridLayout()
                }
                if drawerView.layout.isEmpty {
                    updated.drawerViews.removeValue(forKey: drawerId)
                } else {
                    if drawerView.activeChildId == paneId {
                        drawerView.activeChildId = drawerView.layout.paneIds.first {
                            !drawerView.minimizedPaneIds.contains($0)
                        }
                    }
                    updated.drawerViews[drawerId] = drawerView
                }
            }
            if updated.layout.contains(paneId),
                let newLayout = updated.layout.removing(paneId: paneId, sizingMode: .halveTarget)
            {
                updated.layout = newLayout
            } else if updated.layout.contains(paneId) {
                updated.layout = Layout()
            }
            updated.minimizedPaneIds.remove(paneId)
            if updated.activePaneId == paneId {
                updated.activePaneId = TabArrangementSelectionRules.firstUnminimizedPaneId(in: updated)
            }
            return updated
        }
    }

    static func pruningInvalidPaneIds(
        validPaneIds: Set<UUID>,
        from arrangements: [PaneArrangement]
    ) -> [PaneArrangement] {
        arrangements.map { arrangement in
            var updated = arrangement
            let invalidIds = updated.layout.paneIds.filter { !validPaneIds.contains($0) }
            for paneId in invalidIds {
                if let newLayout = updated.layout.removing(paneId: paneId, sizingMode: .halveTarget) {
                    updated.layout = newLayout
                } else {
                    updated.layout = Layout()
                }
                updated.minimizedPaneIds.remove(paneId)
                if updated.activePaneId == paneId {
                    updated.activePaneId = TabArrangementSelectionRules.firstUnminimizedPaneId(in: updated)
                }
            }
            updated.drawerViews = pruningInvalidDrawerPaneIds(validPaneIds: validPaneIds, from: updated.drawerViews)
            return updated
        }
    }

    private static func pruningInvalidDrawerPaneIds(
        validPaneIds: Set<UUID>,
        from drawerViews: [UUID: DrawerView]
    ) -> [UUID: DrawerView] {
        var updatedDrawerViews = drawerViews
        for drawerId in updatedDrawerViews.keys {
            guard var drawerView = updatedDrawerViews[drawerId] else { continue }
            let invalidIds = drawerView.layout.paneIds.filter { !validPaneIds.contains($0) }
            for paneId in invalidIds {
                drawerView.layout =
                    drawerView.layout.removing(paneId: paneId, sizingMode: .proportional)
                    ?? DrawerGridLayout()
            }
            drawerView.minimizedPaneIds = drawerView.minimizedPaneIds.intersection(drawerView.layout.paneIds)

            guard !drawerView.layout.isEmpty else {
                updatedDrawerViews.removeValue(forKey: drawerId)
                continue
            }

            if let activeChildId = drawerView.activeChildId,
                drawerView.layout.contains(activeChildId),
                !drawerView.minimizedPaneIds.contains(activeChildId)
            {
                updatedDrawerViews[drawerId] = drawerView
                continue
            }

            drawerView.activeChildId = drawerView.layout.paneIds.first {
                !drawerView.minimizedPaneIds.contains($0)
            }
            updatedDrawerViews[drawerId] = drawerView
        }
        return updatedDrawerViews
    }
}
