import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct RearrangeIndexAdjustmentTests {
    @Test
    func sameRow_sourceBeforeTarget_shiftsByMinusOne() {
        let adjustedIndex = RearrangeIndexAdjustment.adjustedInsertionIndex(
            sourceRow: TestRearrangeRow.main,
            sourceIndex: 1,
            targetRow: TestRearrangeRow.main,
            originalInsertionIndex: 3
        )

        #expect(adjustedIndex == 2)
    }

    @Test
    func sameRow_sourceAfterTarget_unchanged() {
        let adjustedIndex = RearrangeIndexAdjustment.adjustedInsertionIndex(
            sourceRow: TestRearrangeRow.main,
            sourceIndex: 3,
            targetRow: TestRearrangeRow.main,
            originalInsertionIndex: 1
        )

        #expect(adjustedIndex == 1)
    }

    @Test
    func sameRow_sourceEqualsTargetSlot_becomesNoOp() {
        let adjustedIndex = RearrangeIndexAdjustment.adjustedInsertionIndex(
            sourceRow: TestRearrangeRow.main,
            sourceIndex: 2,
            targetRow: TestRearrangeRow.main,
            originalInsertionIndex: 3
        )

        #expect(adjustedIndex == 2)
    }

    @Test
    func sameRow_sourceEqualsOriginalInsertionIndex_unchanged() {
        let adjustedIndex = RearrangeIndexAdjustment.adjustedInsertionIndex(
            sourceRow: TestRearrangeRow.main,
            sourceIndex: 2,
            targetRow: TestRearrangeRow.main,
            originalInsertionIndex: 2
        )

        #expect(adjustedIndex == 2)
    }

    @Test
    func sameRow_moveToEndSlot_stillShiftsWhenSourceIsEarlier() {
        let adjustedIndex = RearrangeIndexAdjustment.adjustedInsertionIndex(
            sourceRow: TestRearrangeRow.drawerTop,
            sourceIndex: 1,
            targetRow: TestRearrangeRow.drawerTop,
            originalInsertionIndex: 4
        )

        #expect(adjustedIndex == 3)
    }

    @Test
    func crossRow_unchanged() {
        let adjustedIndex = RearrangeIndexAdjustment.adjustedInsertionIndex(
            sourceRow: TestRearrangeRow.drawerTop,
            sourceIndex: 0,
            targetRow: TestRearrangeRow.drawerBottom,
            originalInsertionIndex: 2
        )

        #expect(adjustedIndex == 2)
    }
}

private enum TestRearrangeRow: Equatable {
    case main
    case drawerTop
    case drawerBottom
}
