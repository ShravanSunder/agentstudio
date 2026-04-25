import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DrawerGridLayoutRearrangeTests {
    private func requireSuccess(
        _ result: Result<DrawerGridLayout, DrawerProjectedMoveFailure>,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> DrawerGridLayout {
        switch result {
        case .success(let layout):
            return layout
        case .failure(let failure):
            Issue.record("Expected success, got \(failure)", sourceLocation: sourceLocation)
            throw failure
        }
    }

    @Test
    func oneRow_slotInsertion_beforeMiddleAfter_areDistinct() throws {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let layout = DrawerGridLayout(topRow: Layout.autoTiled([a, b, c]))

        let before = try requireSuccess(
            layout.projectedMove(
                paneId: c,
                target: .rowSlot(row: .top, insertionIndex: 0),
                sizingMode: .proportional
            )
        )
        #expect(before.topRow.paneIds == [c, a, b])

        let middle = try requireSuccess(
            layout.projectedMove(
                paneId: a,
                target: .rowSlot(row: .top, insertionIndex: 2),
                sizingMode: .proportional
            )
        )
        #expect(middle.topRow.paneIds == [b, a, c])

        let after = try requireSuccess(
            layout.projectedMove(
                paneId: a,
                target: .rowSlot(row: .top, insertionIndex: 3),
                sizingMode: .proportional
            )
        )
        #expect(after.topRow.paneIds == [b, c, a])
    }

    @Test
    func oneRow_createSecondRow_topAndBottomBands_createTwoRows() throws {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let layout = DrawerGridLayout(topRow: Layout.autoTiled([a, b, c]))

        let topRow = try requireSuccess(
            layout.projectedMove(
                paneId: c,
                target: .createSecondRow(position: .top),
                sizingMode: .proportional
            )
        )
        #expect(topRow.topRow.paneIds == [c])
        #expect(topRow.bottomRow?.paneIds == [a, b])

        let bottomRow = try requireSuccess(
            layout.projectedMove(
                paneId: a,
                target: .createSecondRow(position: .bottom),
                sizingMode: .proportional
            )
        )
        #expect(bottomRow.topRow.paneIds == [b, c])
        #expect(bottomRow.bottomRow?.paneIds == [a])
    }

    @Test
    func twoRows_rowSlots_moveBetweenRows_withoutCreatingThirdRow() throws {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let d = UUID()
        let layout = DrawerGridLayout(
            topRow: Layout.autoTiled([a, b]),
            bottomRow: Layout.autoTiled([c, d]),
            rowSplitRatio: 0.5
        )

        let movedToBottom = try requireSuccess(
            layout.projectedMove(
                paneId: b,
                target: .rowSlot(row: .bottom, insertionIndex: 1),
                sizingMode: .proportional
            )
        )
        #expect(movedToBottom.topRow.paneIds == [a])
        #expect(movedToBottom.bottomRow?.paneIds == [c, b, d])
    }

    @Test
    func sameRowForwardMove_usesProportionalRemovalAndAdjustedInsertionIndex() throws {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let layout = DrawerGridLayout(
            topRow: Layout(
                panes: [
                    .init(paneId: a, ratio: 0.5),
                    .init(paneId: b, ratio: 0.3),
                    .init(paneId: c, ratio: 0.2),
                ],
                dividerIds: [UUID(), UUID()]
            )
        )

        let moved = try requireSuccess(
            layout.projectedMove(
                paneId: a,
                target: .rowSlot(row: .top, insertionIndex: 3),
                sizingMode: .proportional
            )
        )

        #expect(moved.topRow.paneIds == [b, c, a])
        expectApprox(moved.topRow.ratios, [0.4, 0.266666666667, 0.333333333333])
    }

    @Test
    func paneSplitTarget_halveTargetSplitsDestinationPaneRatio() throws {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let layout = DrawerGridLayout(
            topRow: Layout(
                panes: [
                    .init(paneId: a, ratio: 0.5),
                    .init(paneId: b, ratio: 0.3),
                    .init(paneId: c, ratio: 0.2),
                ],
                dividerIds: [UUID(), UUID()]
            )
        )

        let moved = try requireSuccess(
            layout.projectedMove(
                paneId: c,
                target: .paneSplit(paneId: a, side: .left),
                sizingMode: .halveTarget
            )
        )

        #expect(moved.topRow.paneIds == [c, a, b])
        expectApprox(moved.topRow.ratios, [0.3125, 0.3125, 0.375])
    }

    @Test
    func paneSplitTarget_proportionalModePreservesSlotInsertionSemantics() throws {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let layout = DrawerGridLayout(
            topRow: Layout(
                panes: [
                    .init(paneId: a, ratio: 0.5),
                    .init(paneId: b, ratio: 0.3),
                    .init(paneId: c, ratio: 0.2),
                ],
                dividerIds: [UUID(), UUID()]
            )
        )

        let moved = try requireSuccess(
            layout.projectedMove(
                paneId: c,
                target: .paneSplit(paneId: a, side: .left),
                sizingMode: .proportional
            )
        )

        #expect(moved.topRow.paneIds == [c, a, b])
        expectApprox(moved.topRow.ratios, [0.333333333333, 0.416666666667, 0.25])
    }

    @Test
    func crossRowMove_usesProportionalRemovalOnSourceAndInsertionOnTarget() throws {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let d = UUID()
        let e = UUID()
        let layout = DrawerGridLayout(
            topRow: Layout(
                panes: [
                    .init(paneId: a, ratio: 0.5),
                    .init(paneId: b, ratio: 0.3),
                    .init(paneId: c, ratio: 0.2),
                ],
                dividerIds: [UUID(), UUID()]
            ),
            bottomRow: Layout(
                panes: [
                    .init(paneId: d, ratio: 0.6),
                    .init(paneId: e, ratio: 0.4),
                ],
                dividerIds: [UUID()]
            )
        )

        let moved = try requireSuccess(
            layout.projectedMove(
                paneId: b,
                target: .rowSlot(row: .bottom, insertionIndex: 1),
                sizingMode: .proportional
            )
        )

        #expect(moved.topRow.paneIds == [a, c])
        #expect(moved.bottomRow?.paneIds == [d, b, e])
        expectApprox(moved.topRow.ratios, [0.714285714286, 0.285714285714])
        expectApprox(moved.bottomRow?.ratios ?? [], [0.4, 0.333333333333, 0.266666666667])
    }

    @Test
    func twoRows_createSecondRowTarget_isRejected() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let layout = DrawerGridLayout(
            topRow: Layout.autoTiled([a, b]),
            bottomRow: Layout.autoTiled([c]),
            rowSplitRatio: 0.5
        )

        #expect(
            layout.projectedMove(
                paneId: a,
                target: .createSecondRow(position: .bottom),
                sizingMode: .proportional
            ) == .failure(.secondRowAlreadyExists)
        )
    }

    @Test
    func twoRows_createSecondRowFromOnlyBottomSource_isRejected() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let layout = DrawerGridLayout(
            topRow: Layout.autoTiled([a, b]),
            bottomRow: Layout.autoTiled([c]),
            rowSplitRatio: 0.5
        )

        #expect(
            layout.projectedMove(
                paneId: c,
                target: .createSecondRow(position: .bottom),
                sizingMode: .proportional
            ) == .failure(.secondRowAlreadyExists)
        )
    }

    @Test
    func missingSourcePane_returnsTypedFailure() {
        let a = UUID()
        let missing = UUID()
        let layout = DrawerGridLayout(topRow: Layout.autoTiled([a]))

        #expect(
            layout.projectedMove(
                paneId: missing,
                target: .rowSlot(row: .top, insertionIndex: 0),
                sizingMode: .proportional
            ) == .failure(.missingSourcePane(missing))
        )
    }

    @Test
    func sourceRemovalRejected_returnsTypedFailure() {
        let onlyPane = UUID()
        let layout = DrawerGridLayout(topRow: Layout.autoTiled([onlyPane]))

        #expect(
            layout.projectedMove(
                paneId: onlyPane,
                target: .rowSlot(row: .top, insertionIndex: 0),
                sizingMode: .proportional
            ) == .failure(.sourceRemovalRejected(onlyPane))
        )
    }

    @Test
    func missingPaneSplitTarget_returnsTypedFailure() {
        let a = UUID()
        let b = UUID()
        let missingTarget = UUID()
        let layout = DrawerGridLayout(topRow: Layout.autoTiled([a, b]))

        #expect(
            layout.projectedMove(
                paneId: b,
                target: .paneSplit(paneId: missingTarget, side: .left),
                sizingMode: .halveTarget
            ) == .failure(.missingTargetPane(missingTarget))
        )
    }

    @Test
    func missingBottomRowSlot_returnsTypedFailure() {
        let a = UUID()
        let b = UUID()
        let layout = DrawerGridLayout(topRow: Layout.autoTiled([a, b]))

        #expect(
            layout.projectedMove(
                paneId: a,
                target: .rowSlot(row: .bottom, insertionIndex: 0),
                sizingMode: .proportional
            ) == .failure(.missingBottomRow)
        )
    }

    @Test
    func invalidBottomRowInsertionIndex_returnsTypedFailure() {
        let a = UUID()
        let d = UUID()
        let b = UUID()
        let c = UUID()
        let layout = DrawerGridLayout(
            topRow: Layout.autoTiled([a, d]),
            bottomRow: Layout.autoTiled([b, c]),
            rowSplitRatio: 0.5
        )

        #expect(
            layout.projectedMove(
                paneId: a,
                target: .rowSlot(row: .bottom, insertionIndex: 4),
                sizingMode: .proportional
            ) == .failure(.invalidInsertionIndex(row: .bottom, insertionIndex: 4, paneCount: 2))
        )
    }

    /// P2 — solo-row drag-out to a row-slot in the OTHER row.
    /// Removing the source from a solo top row collapses the layout to
    /// single-row (bottom panes promoted to top). The resolver
    /// legitimately returns `.rowSlot(row: .bottom, ...)` referring
    /// to the user's intent of "drop into the other row." The apply
    /// path must normalize the target row to the post-collapse layout
    /// shape so the insertion lands in what was the bottom row (now
    /// the only row).
    @Test
    func soloTopRow_dragToBottomRowSlot_collapsesAndInsertsAtIndex() throws {
        let s = UUID()
        let b1 = UUID()
        let b2 = UUID()
        let layout = DrawerGridLayout(
            topRow: Layout.autoTiled([s]),
            bottomRow: Layout.autoTiled([b1, b2]),
            rowSplitRatio: 0.5
        )

        // User intent: drop S between B1 and B2 (slot 1 of bottom row).
        let result = try requireSuccess(
            layout.projectedMove(
                paneId: s,
                target: .rowSlot(row: .bottom, insertionIndex: 1),
                sizingMode: .proportional
            )
        )

        // Top row collapsed to bottom contents, S inserted at index 1.
        #expect(result.topRow.paneIds == [b1, s, b2])
        #expect(result.bottomRow == nil)
    }

    @Test
    func soloTopRow_dragToBottomRowSlot_atStart_insertsAtZero() throws {
        let s = UUID()
        let b1 = UUID()
        let b2 = UUID()
        let layout = DrawerGridLayout(
            topRow: Layout.autoTiled([s]),
            bottomRow: Layout.autoTiled([b1, b2]),
            rowSplitRatio: 0.5
        )

        let result = try requireSuccess(
            layout.projectedMove(
                paneId: s,
                target: .rowSlot(row: .bottom, insertionIndex: 0),
                sizingMode: .proportional
            )
        )

        #expect(result.topRow.paneIds == [s, b1, b2])
        #expect(result.bottomRow == nil)
    }

    @Test
    func soloTopRow_dragToBottomRowSlot_atEnd_insertsAtCount() throws {
        let s = UUID()
        let b1 = UUID()
        let b2 = UUID()
        let layout = DrawerGridLayout(
            topRow: Layout.autoTiled([s]),
            bottomRow: Layout.autoTiled([b1, b2]),
            rowSplitRatio: 0.5
        )

        let result = try requireSuccess(
            layout.projectedMove(
                paneId: s,
                target: .rowSlot(row: .bottom, insertionIndex: 2),
                sizingMode: .proportional
            )
        )

        #expect(result.topRow.paneIds == [b1, b2, s])
        #expect(result.bottomRow == nil)
    }

    /// Codex P2 — when source is the SOLO pane in the bottom row and
    /// the target is `.rowSlot(.bottom, ...)`, the previous P2 fix
    /// silently normalized to `.top` because removing source from solo
    /// bottom collapsed that row. That turned a self-row no-op into a
    /// real top-row insertion.
    ///
    /// The resolver's R1+R2 should reject in-source-row targets, but a
    /// stale or direct command can bypass to the apply path. Defensive
    /// rejection here keeps the model honest.
    @Test
    func soloBottomRow_dragToOwnBottomRowSlot_returnsMissingBottomRow() {
        let s = UUID()
        let t1 = UUID()
        let layout = DrawerGridLayout(
            topRow: Layout.autoTiled([t1]),
            bottomRow: Layout.autoTiled([s]),
            rowSplitRatio: 0.5
        )

        // Source is alone in bottom; target is bottom slot 0 (its own row).
        // Removing source collapses bottom; normalization MUST NOT silently
        // rewrite this to top — the user's intent was bottom-row slot.
        let result = layout.projectedMove(
            paneId: s,
            target: .rowSlot(row: .bottom, insertionIndex: 0),
            sizingMode: .proportional
        )

        #expect(result == .failure(.missingBottomRow))
    }

    private func expectApprox(
        _ actual: [Double],
        _ expected: [Double],
        tolerance: Double = 0.000001,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(actual.count == expected.count, sourceLocation: sourceLocation)
        for (actualRatio, expectedRatio) in zip(actual, expected) {
            #expect(abs(actualRatio - expectedRatio) < tolerance, sourceLocation: sourceLocation)
        }
        #expect(abs(actual.reduce(0, +) - 1.0) < tolerance, sourceLocation: sourceLocation)
    }
}
