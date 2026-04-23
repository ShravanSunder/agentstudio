import Foundation

enum VisibleRowIndexMapping {
    static func fullRowIndex(
        forVisibleSlot visibleIndex: Int,
        fullRow: [UUID],
        minimizedPaneIds: Set<UUID>,
        showMinimizedBars: Bool
    ) -> Int {
        if showMinimizedBars {
            return visibleIndex
        }

        var seenVisiblePaneCount = 0
        for (fullIndex, paneId) in fullRow.enumerated() {
            if minimizedPaneIds.contains(paneId) {
                continue
            }
            if seenVisiblePaneCount == visibleIndex {
                return fullIndex
            }
            seenVisiblePaneCount += 1
        }

        return fullRow.count
    }
}
