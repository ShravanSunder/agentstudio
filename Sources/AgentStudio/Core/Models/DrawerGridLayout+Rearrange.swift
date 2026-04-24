import Foundation

enum DrawerProjectedMoveFailure: Error, Equatable, Hashable, Sendable, CustomStringConvertible {
    case missingSourcePane(UUID)
    case sourceRemovalRejected(UUID)
    case secondRowAlreadyExists
    case missingBottomRow
    case invalidInsertionIndex(row: DrawerRowPlacement, insertionIndex: Int, paneCount: Int)

    var description: String {
        switch self {
        case .missingSourcePane(let paneId):
            return "missingSourcePane(\(paneId))"
        case .sourceRemovalRejected(let paneId):
            return "sourceRemovalRejected(\(paneId))"
        case .secondRowAlreadyExists:
            return "secondRowAlreadyExists"
        case .missingBottomRow:
            return "missingBottomRow"
        case .invalidInsertionIndex(let row, let insertionIndex, let paneCount):
            return "invalidInsertionIndex(row: \(row), insertionIndex: \(insertionIndex), paneCount: \(paneCount))"
        }
    }
}

extension DrawerGridLayout {
    func projectedMove(
        paneId: UUID,
        target: DrawerRearrangeTarget,
        sizingMode: DropSizingMode
    ) -> Result<DrawerGridLayout, DrawerProjectedMoveFailure> {
        guard let sourceLocation = location(of: paneId) else {
            return .failure(.missingSourcePane(paneId))
        }
        guard let layoutWithoutSource = removing(paneId: paneId, sizingMode: .proportional) else {
            return .failure(.sourceRemovalRejected(paneId))
        }

        switch target {
        case .rowSlot(let row, let insertionIndex):
            let adjustedInsertionIndex = RearrangeIndexAdjustment.adjustedInsertionIndex(
                sourceRow: sourceLocation.row,
                sourceIndex: sourceLocation.index,
                targetRow: row,
                originalInsertionIndex: insertionIndex
            )
            return layoutWithoutSource.insertingAtSlot(
                paneId: paneId,
                row: row,
                insertionIndex: adjustedInsertionIndex,
                sizingMode: sizingMode
            )
        case .createSecondRow(let position):
            guard bottomRow == nil else {
                return .failure(.secondRowAlreadyExists)
            }
            return .success(
                layoutWithoutSource.creatingSecondRow(
                    paneId: paneId,
                    position: position
                ))
        }
    }

    private func insertingAtSlot(
        paneId: UUID,
        row: DrawerRowPlacement,
        insertionIndex: Int,
        sizingMode: DropSizingMode
    ) -> Result<DrawerGridLayout, DrawerProjectedMoveFailure> {
        switch row {
        case .top:
            guard (0...topRow.paneIds.count).contains(insertionIndex) else {
                return .failure(
                    .invalidInsertionIndex(
                        row: .top,
                        insertionIndex: insertionIndex,
                        paneCount: topRow.paneIds.count
                    )
                )
            }
            let updated = topRow.insertingWithPolicy(
                paneId: paneId,
                insertionIndex: insertionIndex,
                sizingMode: sizingMode
            )
            return .success(
                DrawerGridLayout(
                    topRow: updated,
                    bottomRow: bottomRow,
                    rowSplitRatio: rowSplitRatio
                ))
        case .bottom:
            guard let bottomRow else { return .failure(.missingBottomRow) }
            guard (0...bottomRow.paneIds.count).contains(insertionIndex) else {
                return .failure(
                    .invalidInsertionIndex(
                        row: .bottom,
                        insertionIndex: insertionIndex,
                        paneCount: bottomRow.paneIds.count
                    )
                )
            }
            let updated = bottomRow.insertingWithPolicy(
                paneId: paneId,
                insertionIndex: insertionIndex,
                sizingMode: sizingMode
            )
            return .success(
                DrawerGridLayout(
                    topRow: topRow,
                    bottomRow: updated,
                    rowSplitRatio: rowSplitRatio
                ))
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

    func legacyMoveTarget(
        targetPaneId: UUID,
        direction: SplitNewDirection
    ) -> DrawerRearrangeTarget? {
        let topPaneIds = topRow.paneIds
        let bottomPaneIds = bottomRow?.paneIds ?? []

        if let topIndex = topPaneIds.firstIndex(of: targetPaneId) {
            switch direction {
            case .left:
                return .rowSlot(row: .top, insertionIndex: topIndex)
            case .right:
                return .rowSlot(row: .top, insertionIndex: topIndex + 1)
            case .up:
                if bottomRow == nil {
                    return .createSecondRow(position: .top)
                }
                return nil
            case .down:
                if let bottomRow {
                    return .rowSlot(
                        row: .bottom,
                        insertionIndex: min(topIndex, bottomRow.paneIds.count)
                    )
                }
                return .createSecondRow(position: .bottom)
            }
        }

        if let bottomIndex = bottomPaneIds.firstIndex(of: targetPaneId) {
            switch direction {
            case .left:
                return .rowSlot(row: .bottom, insertionIndex: bottomIndex)
            case .right:
                return .rowSlot(row: .bottom, insertionIndex: bottomIndex + 1)
            case .up:
                return .rowSlot(
                    row: .top,
                    insertionIndex: min(bottomIndex, topPaneIds.count)
                )
            case .down:
                return nil
            }
        }

        return nil
    }

    private func location(of paneId: UUID) -> (row: DrawerRowPlacement, index: Int)? {
        if let index = topRow.paneIds.firstIndex(of: paneId) {
            return (.top, index)
        }
        if let index = bottomRow?.paneIds.firstIndex(of: paneId) {
            return (.bottom, index)
        }
        return nil
    }
}

extension Layout {
    fileprivate func insertingWithPolicy(
        paneId: UUID,
        insertionIndex: Int,
        sizingMode: DropSizingMode
    ) -> Layout {
        if paneIds.isEmpty {
            return Layout(paneId: paneId)
        }
        let clampedIndex = max(0, min(insertionIndex, paneIds.count))
        let updatedRatios = DropSizingRatioPolicy.ratiosAfterInsertion(
            existingRatios: ratios,
            insertionIndex: clampedIndex,
            mode: insertionSizingMode(
                for: sizingMode,
                insertionIndex: clampedIndex,
                paneCount: paneIds.count,
                preferredTargetPaneIndex: nil
            )
        )
        return inserting(paneId: paneId, atIndex: clampedIndex, ratios: updatedRatios)
    }
}
