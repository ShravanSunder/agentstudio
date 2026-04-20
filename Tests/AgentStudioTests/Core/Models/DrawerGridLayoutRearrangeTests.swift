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
                target: .rowSlot(row: .top, insertionIndex: 0)
            )
        )
        #expect(before.topRow.paneIds == [c, a, b])

        let middle = try #require(
            layout.projectedMove(
                paneId: a,
                target: .rowSlot(row: .top, insertionIndex: 1)
            )
        )
        #expect(middle.topRow.paneIds == [b, a, c])

        let after = try #require(
            layout.projectedMove(
                paneId: a,
                target: .rowSlot(row: .top, insertionIndex: 2)
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
                target: .createSecondRow(position: .top)
            )
        )
        #expect(topRow.topRow.paneIds == [c])
        #expect(topRow.bottomRow?.paneIds == [a, b])

        let bottomRow = try #require(
            layout.projectedMove(
                paneId: a,
                target: .createSecondRow(position: .bottom)
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
                target: .rowSlot(row: .bottom, insertionIndex: 1)
            )
        )
        #expect(movedToBottom.topRow.paneIds == [a])
        #expect(movedToBottom.bottomRow?.paneIds == [c, b, d])
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
                target: .createSecondRow(position: .bottom)
            ) == nil
        )
    }
}
