import Foundation

enum TabArrangementRepairRules {
    static func removingPane(
        _ paneId: UUID,
        removingDrawerIds drawerIds: Set<UUID> = [],
        layoutSizingMode: DropSizingMode = .halveTarget,
        from arrangements: [PaneArrangement]
    ) -> [PaneArrangement] {
        removingPanes(
            Set([paneId]),
            removingDrawerIds: drawerIds,
            layoutSizingMode: layoutSizingMode,
            from: arrangements
        )
    }

    static func removingPanes(
        _ paneIds: Set<UUID>,
        removingDrawerIds drawerIds: Set<UUID> = [],
        layoutSizingMode: DropSizingMode = .halveTarget,
        from arrangements: [PaneArrangement]
    ) -> [PaneArrangement] {
        arrangements.map { arrangement in
            var updated = arrangement
            for drawerId in drawerIds {
                updated.drawerViews.removeValue(forKey: drawerId)
            }
            updated.drawerViews = pruningInvalidDrawerViewPaneIds(
                validPaneIds: Set(
                    updated.drawerViews.flatMap { $0.value.layout.paneIds }.filter { !paneIds.contains($0) }),
                from: updated.drawerViews
            )
            for paneId in paneIds where updated.layout.contains(paneId) {
                if let newLayout = updated.layout.removing(paneId: paneId, sizingMode: layoutSizingMode) {
                    updated.layout = newLayout
                } else {
                    updated.layout = Layout()
                }
            }
            updated.minimizedPaneIds.subtract(paneIds)
            if let activePaneId = updated.activePaneId, paneIds.contains(activePaneId) {
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
                updated.minimizedPaneIds.remove(paneId)
                if updated.activePaneId == paneId {
                    updated.activePaneId = TabArrangementSelectionRules.firstUnminimizedPaneId(in: updated)
                }
            }
            updated.layout = pruningInvalidPaneIds(validPaneIds: validPaneIds, from: updated.layout)
            updated.drawerViews = pruningInvalidDrawerViewPaneIds(validPaneIds: validPaneIds, from: updated.drawerViews)
            return updated
        }
    }

    static func pruningInvalidDrawerViewPaneIds(
        validPaneIds: Set<UUID>,
        from drawerViews: [UUID: DrawerView]
    ) -> [UUID: DrawerView] {
        var updated = drawerViews
        for drawerId in Array(updated.keys) {
            guard var drawerView = updated[drawerId] else { continue }
            drawerView.layout = pruningInvalidPaneIds(validPaneIds: validPaneIds, from: drawerView.layout)
            drawerView.minimizedPaneIds.formIntersection(drawerView.layout.paneIds)

            if drawerView.layout.isEmpty {
                updated.removeValue(forKey: drawerId)
                continue
            }

            if let activeChildId = drawerView.activeChildId,
                drawerView.layout.contains(activeChildId),
                !drawerView.minimizedPaneIds.contains(activeChildId)
            {
                updated[drawerId] = drawerView
                continue
            }

            drawerView.activeChildId = drawerView.layout.paneIds.first {
                !drawerView.minimizedPaneIds.contains($0)
            }
            updated[drawerId] = drawerView
        }
        return updated
    }

    private static func pruningInvalidPaneIds(validPaneIds: Set<UUID>, from layout: Layout) -> Layout {
        var updated = layout
        let invalidIds = updated.paneIds.filter { !validPaneIds.contains($0) }
        for paneId in invalidIds {
            if let newLayout = updated.removing(paneId: paneId, sizingMode: .halveTarget) {
                updated = newLayout
            } else {
                updated = Layout()
            }
        }
        return updated
    }

    private static func pruningInvalidPaneIds(
        validPaneIds: Set<UUID>,
        from layout: DrawerGridLayout
    ) -> DrawerGridLayout {
        let topRow = pruningInvalidPaneIds(validPaneIds: validPaneIds, from: layout.topRow)
        let bottomRow = layout.bottomRow.map { pruningInvalidPaneIds(validPaneIds: validPaneIds, from: $0) }
        if topRow.isEmpty, let bottomRow, !bottomRow.isEmpty {
            return DrawerGridLayout(topRow: bottomRow, rowSplitRatio: layout.rowSplitRatio)
        }
        return DrawerGridLayout(
            topRow: topRow,
            bottomRow: bottomRow?.isEmpty == true ? nil : bottomRow,
            rowSplitRatio: layout.rowSplitRatio
        )
    }
}
