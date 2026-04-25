import Foundation

enum DrawerProjectedMoveFailure: Error, Equatable, Hashable, Sendable, CustomStringConvertible {
    case missingSourcePane(UUID)
    case missingTargetPane(UUID)
    case sourceRemovalRejected(UUID)
    case secondRowAlreadyExists
    case missingBottomRow
    case invalidInsertionIndex(row: DrawerRowPlacement, insertionIndex: Int, paneCount: Int)
    case invalidSizingTarget(paneIndex: Int, paneCount: Int)

    var description: String {
        switch self {
        case .missingSourcePane(let paneId):
            return "missingSourcePane(\(paneId))"
        case .missingTargetPane(let paneId):
            return "missingTargetPane(\(paneId))"
        case .sourceRemovalRejected(let paneId):
            return "sourceRemovalRejected(\(paneId))"
        case .secondRowAlreadyExists:
            return "secondRowAlreadyExists"
        case .missingBottomRow:
            return "missingBottomRow"
        case .invalidInsertionIndex(let row, let insertionIndex, let paneCount):
            return "invalidInsertionIndex(row: \(row), insertionIndex: \(insertionIndex), paneCount: \(paneCount))"
        case .invalidSizingTarget(let paneIndex, let paneCount):
            return "invalidSizingTarget(paneIndex: \(paneIndex), paneCount: \(paneCount))"
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
        case .paneSplit(let targetPaneId, let side):
            guard let targetLocation = layoutWithoutSource.location(of: targetPaneId) else {
                return .failure(.missingTargetPane(targetPaneId))
            }
            let insertionIndex = targetLocation.index + (side == .right ? 1 : 0)
            return layoutWithoutSource.insertingAtSlot(
                paneId: paneId,
                row: targetLocation.row,
                insertionIndex: insertionIndex,
                sizingMode: sizingMode,
                preferredTargetPaneIndex: targetLocation.index
            )
        case .rowSlot(let row, let insertionIndex):
            // The same-row index-shift correction must use the ORIGINAL
            // target row (pre-collapse) so a cross-row drop with no
            // adjustment stays uncorrected.
            let adjustedInsertionIndex = RearrangeIndexAdjustment.adjustedInsertionIndex(
                sourceRow: sourceLocation.row,
                sourceIndex: sourceLocation.index,
                targetRow: row,
                originalInsertionIndex: insertionIndex
            )
            // When source's removal collapses its solo row (bottom
            // existed before, now doesn't), the user's intent of "drop
            // into the OTHER row" maps to "drop into the now-only row".
            // We only redirect when the collapse actually happened —
            // a target of .bottom on a layout that never had a bottom
            // row stays as-is so the caller still gets .missingBottomRow.
            let normalizedRow: DrawerRowPlacement
            if row == .bottom, bottomRow != nil, layoutWithoutSource.bottomRow == nil {
                normalizedRow = .top
            } else {
                normalizedRow = row
            }
            return layoutWithoutSource.insertingAtSlot(
                paneId: paneId,
                row: normalizedRow,
                insertionIndex: adjustedInsertionIndex,
                sizingMode: sizingMode,
                preferredTargetPaneIndex: nil
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
        sizingMode: DropSizingMode,
        preferredTargetPaneIndex: Int?
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
            guard
                let updated = topRow.insertingWithPolicy(
                    paneId: paneId,
                    insertionIndex: insertionIndex,
                    sizingMode: sizingMode,
                    preferredTargetPaneIndex: preferredTargetPaneIndex
                )
            else {
                return .failure(
                    .invalidSizingTarget(
                        paneIndex: preferredTargetPaneIndex ?? insertionIndex,
                        paneCount: topRow.paneIds.count
                    )
                )
            }
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
            guard
                let updated = bottomRow.insertingWithPolicy(
                    paneId: paneId,
                    insertionIndex: insertionIndex,
                    sizingMode: sizingMode,
                    preferredTargetPaneIndex: preferredTargetPaneIndex
                )
            else {
                return .failure(
                    .invalidSizingTarget(
                        paneIndex: preferredTargetPaneIndex ?? insertionIndex,
                        paneCount: bottomRow.paneIds.count
                    )
                )
            }
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
        sizingMode: DropSizingMode,
        preferredTargetPaneIndex: Int?
    ) -> Layout? {
        if paneIds.isEmpty {
            return Layout(paneId: paneId)
        }
        let clampedIndex = max(0, min(insertionIndex, paneIds.count))
        guard
            let insertionSizingMode = insertionSizingMode(
                for: sizingMode,
                insertionIndex: clampedIndex,
                paneCount: paneIds.count,
                preferredTargetPaneIndex: preferredTargetPaneIndex
            )
        else {
            return nil
        }

        let updatedRatios = DropSizingRatioPolicy.ratiosAfterInsertion(
            existingRatios: ratios,
            insertionIndex: clampedIndex,
            mode: insertionSizingMode
        )
        return inserting(paneId: paneId, atIndex: clampedIndex, ratios: updatedRatios)
    }
}
