import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DrawerGridLayoutRearrangeTests {
    @Test
    func oneRow_slotInsertion_beforeMiddleAfter_areDistinct() throws {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let layout = DrawerGridLayout(topRow: Layout.autoTiled([a, b, c]))

        let before = try #require(
            layout.projectedMove(
                paneId: c,
                target: .rowSlot(row: .top, insertionIndex: 0),
                sizingMode: .proportional
            )
        )
        #expect(before.topRow.paneIds == [c, a, b])

        let middle = try #require(
            layout.projectedMove(
                paneId: a,
                target: .rowSlot(row: .top, insertionIndex: 2),
                sizingMode: .proportional
            )
        )
        #expect(middle.topRow.paneIds == [b, a, c])

        let after = try #require(
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

        let topRow = try #require(
            layout.projectedMove(
                paneId: c,
                target: .createSecondRow(position: .top),
                sizingMode: .proportional
            )
        )
        #expect(topRow.topRow.paneIds == [c])
        #expect(topRow.bottomRow?.paneIds == [a, b])

        let bottomRow = try #require(
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

        let movedToBottom = try #require(
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

        let moved = try #require(
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

        let moved = try #require(
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
            ) == nil
        )
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
