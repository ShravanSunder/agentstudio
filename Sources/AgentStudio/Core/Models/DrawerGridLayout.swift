import Foundation

struct DrawerGridLayout: Codable, Hashable {
    var topRow: Layout
    var bottomRow: Layout?
    var rowSplitRatio: Double

    init(
        topRow: Layout = Layout(),
        bottomRow: Layout? = nil,
        rowSplitRatio: Double = 0.5
    ) {
        self.topRow = topRow
        self.bottomRow = bottomRow
        self.rowSplitRatio = rowSplitRatio
    }

    var paneIds: [UUID] {
        topRow.paneIds + (bottomRow?.paneIds ?? [])
    }

    var dividerIds: [UUID] {
        topRow.dividerIds + (bottomRow?.dividerIds ?? [])
    }

    var isEmpty: Bool {
        topRow.isEmpty && bottomRow == nil
    }

    func contains(_ paneId: UUID) -> Bool {
        topRow.contains(paneId) || bottomRow?.contains(paneId) == true
    }

    func neighbor(of paneId: UUID, direction: FocusDirection) -> UUID? {
        switch direction {
        case .left, .right:
            if topRow.contains(paneId) {
                return topRow.neighbor(of: paneId, direction: direction)
            }
            return bottomRow?.neighbor(of: paneId, direction: direction)
        case .up:
            guard let bottomRow, bottomRow.contains(paneId) else { return nil }
            return pairedPane(in: topRow, for: paneId, from: bottomRow)
        case .down:
            guard let bottomRow, topRow.contains(paneId) else { return nil }
            return pairedPane(in: bottomRow, for: paneId, from: topRow)
        }
    }

    func inserting(
        paneId: UUID,
        at targetPaneId: UUID,
        direction: SplitNewDirection,
        sizingMode: DropSizingMode
    ) -> Self? {
        switch direction {
        case .left:
            return insertingHorizontally(
                paneId: paneId,
                at: targetPaneId,
                position: .before,
                sizingMode: sizingMode
            )
        case .right:
            return insertingHorizontally(
                paneId: paneId,
                at: targetPaneId,
                position: .after,
                sizingMode: sizingMode
            )
        case .up:
            if topRow.contains(targetPaneId) {
                guard bottomRow == nil else { return nil }
                return Self(
                    topRow: Layout(paneId: paneId),
                    bottomRow: topRow,
                    rowSplitRatio: rowSplitRatio
                )
            }

            guard
                let bottomRow,
                let targetIndex = bottomRow.paneIds.firstIndex(of: targetPaneId)
            else { return nil }

            return Self(
                topRow: horizontallyInserting(
                    paneId: paneId,
                    into: topRow,
                    alignedWith: targetIndex,
                    sizingMode: sizingMode
                ),
                bottomRow: bottomRow,
                rowSplitRatio: rowSplitRatio
            )
        case .down:
            guard let targetIndex = topRow.paneIds.firstIndex(of: targetPaneId) else { return nil }

            if let bottomRow {
                return Self(
                    topRow: topRow,
                    bottomRow: horizontallyInserting(
                        paneId: paneId,
                        into: bottomRow,
                        alignedWith: targetIndex,
                        sizingMode: sizingMode
                    ),
                    rowSplitRatio: rowSplitRatio
                )
            }

            return Self(
                topRow: topRow,
                bottomRow: Layout(paneId: paneId),
                rowSplitRatio: rowSplitRatio
            )
        }
    }

    private func insertingHorizontally(
        paneId: UUID,
        at targetPaneId: UUID,
        position: Layout.Position,
        sizingMode: DropSizingMode
    ) -> Self? {
        if topRow.contains(targetPaneId) {
            guard
                let updatedTopRow = topRow.inserting(
                    paneId: paneId,
                    at: targetPaneId,
                    direction: .horizontal,
                    position: position,
                    sizingMode: sizingMode
                )
            else { return nil }
            return Self(topRow: updatedTopRow, bottomRow: bottomRow, rowSplitRatio: rowSplitRatio)
        }

        guard let bottomRow, bottomRow.contains(targetPaneId) else { return nil }
        guard
            let updatedBottomRow = bottomRow.inserting(
                paneId: paneId,
                at: targetPaneId,
                direction: .horizontal,
                position: position,
                sizingMode: sizingMode
            )
        else { return nil }
        return Self(topRow: topRow, bottomRow: updatedBottomRow, rowSplitRatio: rowSplitRatio)
    }

    func removing(paneId: UUID, sizingMode: DropSizingMode) -> Self? {
        if topRow.contains(paneId) {
            if let updatedTopRow = topRow.removing(paneId: paneId, sizingMode: sizingMode) {
                return Self(
                    topRow: updatedTopRow,
                    bottomRow: bottomRow,
                    rowSplitRatio: rowSplitRatio
                )
            }

            guard let bottomRow else { return nil }
            return Self(
                topRow: bottomRow,
                bottomRow: nil,
                rowSplitRatio: rowSplitRatio
            )
        }

        if let bottomRow, bottomRow.contains(paneId) {
            if let updatedBottomRow = bottomRow.removing(paneId: paneId, sizingMode: sizingMode) {
                return Self(
                    topRow: topRow,
                    bottomRow: updatedBottomRow,
                    rowSplitRatio: rowSplitRatio
                )
            }

            return Self(
                topRow: topRow,
                bottomRow: nil,
                rowSplitRatio: rowSplitRatio
            )
        }

        return nil
    }

    func resizing(splitId: UUID, ratio: Double) -> Self {
        if topRow.dividerIds.contains(splitId) {
            return Self(
                topRow: topRow.resizing(splitId: splitId, ratio: ratio),
                bottomRow: bottomRow,
                rowSplitRatio: rowSplitRatio
            )
        }

        if let bottomRow, bottomRow.dividerIds.contains(splitId) {
            return Self(
                topRow: topRow,
                bottomRow: bottomRow.resizing(splitId: splitId, ratio: ratio),
                rowSplitRatio: rowSplitRatio
            )
        }

        return self
    }

    func equalized() -> Self {
        Self(
            topRow: topRow.equalized(),
            bottomRow: bottomRow?.equalized(),
            rowSplitRatio: rowSplitRatio
        )
    }

    func ratioForSplit(_ splitId: UUID) -> Double? {
        topRow.ratioForSplit(splitId) ?? bottomRow?.ratioForSplit(splitId)
    }

    private func pairedPane(
        in destinationRow: Layout,
        for sourcePaneId: UUID,
        from sourceRow: Layout
    ) -> UUID? {
        guard
            let sourceIndex = sourceRow.paneIds.firstIndex(of: sourcePaneId),
            !destinationRow.paneIds.isEmpty
        else { return nil }

        let pairedIndex = min(sourceIndex, destinationRow.paneIds.count - 1)
        return destinationRow.paneIds[pairedIndex]
    }

    private func horizontallyInserting(
        paneId: UUID,
        into row: Layout,
        alignedWith targetIndex: Int,
        sizingMode: DropSizingMode
    ) -> Layout {
        guard !row.paneIds.isEmpty else { return Layout(paneId: paneId) }

        if targetIndex == 0 {
            return row.inserting(
                paneId: paneId,
                at: row.paneIds[0],
                direction: .horizontal,
                position: .before,
                sizingMode: sizingMode
            ) ?? row
        }

        let anchorIndex = min(targetIndex - 1, row.paneIds.count - 1)
        return row.inserting(
            paneId: paneId,
            at: row.paneIds[anchorIndex],
            direction: .horizontal,
            position: .after,
            sizingMode: sizingMode
        ) ?? row
    }
}
