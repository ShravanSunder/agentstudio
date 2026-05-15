import Foundation

enum TabArrangementRepairRules {
    static func removingPane(_ paneId: UUID, from arrangements: [PaneArrangement]) -> [PaneArrangement] {
        arrangements.map { arrangement in
            var updated = arrangement
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
