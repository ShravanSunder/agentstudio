import Foundation

extension DrawerGridLayout {
    func projectedMove(
        paneId: UUID,
        target: DrawerRearrangeTarget
    ) -> DrawerGridLayout? {
        guard let layoutWithoutSource = removing(paneId: paneId) else { return nil }

        switch target {
        case .rowSlot(let row, let insertionIndex):
            return layoutWithoutSource.insertingAtSlot(
                paneId: paneId,
                row: row,
                insertionIndex: insertionIndex
            )
        case .createSecondRow(let position):
            guard layoutWithoutSource.bottomRow == nil else { return nil }
            return layoutWithoutSource.creatingSecondRow(
                paneId: paneId,
                position: position
            )
        }
    }

    private func insertingAtSlot(
        paneId: UUID,
        row: DrawerRowPlacement,
        insertionIndex: Int
    ) -> DrawerGridLayout? {
        switch row {
        case .top:
            guard (0...topRow.paneIds.count).contains(insertionIndex) else { return nil }
            let updated = topRow.insertingPreservingRatios(
                paneId: paneId,
                insertionIndex: insertionIndex
            )
            return DrawerGridLayout(
                topRow: updated,
                bottomRow: bottomRow,
                rowSplitRatio: rowSplitRatio
            )
        case .bottom:
            guard let bottomRow else { return nil }
            guard (0...bottomRow.paneIds.count).contains(insertionIndex) else { return nil }
            let updated = bottomRow.insertingPreservingRatios(
                paneId: paneId,
                insertionIndex: insertionIndex
            )
            return DrawerGridLayout(
                topRow: topRow,
                bottomRow: updated,
                rowSplitRatio: rowSplitRatio
            )
        }
    }

    private func creatingSecondRow(
        paneId: UUID,
        position: DrawerRowPlacement
    ) -> DrawerGridLayout {
        switch position {
        case .top:
            return DrawerGridLayout(
                topRow: Layout(paneId: paneId),
                bottomRow: topRow,
                rowSplitRatio: rowSplitRatio
            )
        case .bottom:
            return DrawerGridLayout(
                topRow: topRow,
                bottomRow: Layout(paneId: paneId),
                rowSplitRatio: rowSplitRatio
            )
        }
    }
}

extension Layout {
    fileprivate func insertingPreservingRatios(
        paneId: UUID,
        insertionIndex: Int
    ) -> Layout {
        if paneIds.isEmpty {
            return Layout(paneId: paneId)
        }
        if insertionIndex == 0 {
            return inserting(
                paneId: paneId,
                at: paneIds[0],
                direction: .horizontal,
                position: .before
            )
        }
        if insertionIndex >= paneIds.count {
            return inserting(
                paneId: paneId,
                at: paneIds[paneIds.count - 1],
                direction: .horizontal,
                position: .after
            )
        }
        return inserting(
            paneId: paneId,
            at: paneIds[insertionIndex - 1],
            direction: .horizontal,
            position: .after
        )
    }
}
