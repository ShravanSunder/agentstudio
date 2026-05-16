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
            return updated
        }
    }
}
