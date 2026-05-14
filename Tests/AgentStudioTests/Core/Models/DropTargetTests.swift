import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DropTargetTests {
    @Test
    func rowID_mainIsNotDrawer() {
        #expect(RowID.main != .drawerTop)
        #expect(RowID.main != .drawerBottom)
    }

    @Test
    func dropZoneSide_leftRightDistinct() {
        #expect(DropZoneSide.left != .right)
        #expect(DropZoneSide.allCases.count == 2)
    }

    @Test
    func dropTarget_paneSplitEquality() {
        let paneId = UUID()
        let a: DropTarget = .paneSplit(paneId: paneId, side: .left)
        let b: DropTarget = .paneSplit(paneId: paneId, side: .left)
        let c: DropTarget = .paneSplit(paneId: paneId, side: .right)

        #expect(a == b)
        #expect(a != c)
    }

    @Test
    func dropTarget_paneSlotEquality() {
        let a: DropTarget = .paneSlot(row: .main, index: 0)
        let b: DropTarget = .paneSlot(row: .main, index: 0)

        #expect(a == b)
    }

    @Test
    func dropTarget_paneNewRowPositions() {
        #expect(DropTarget.paneNewRow(position: .top) != .paneNewRow(position: .bottom))
    }

    @Test
    func dropTarget_kindsAreDisjoint() {
        let paneId = UUID()
        let split: DropTarget = .paneSplit(paneId: paneId, side: .left)
        let slot: DropTarget = .paneSlot(row: .main, index: 0)
        let newRow: DropTarget = .paneNewRow(position: .top)

        #expect(split != slot)
        #expect(slot != newRow)
        #expect(split != newRow)
    }

    @Test
    func dropTarget_hashable_inSet() {
        let paneId = UUID()
        let set: Set<DropTarget> = [
            .paneSlot(row: .main, index: 0),
            .paneSlot(row: .main, index: 0),
            .paneSlot(row: .drawerTop, index: 1),
            .paneSplit(paneId: paneId, side: .left),
        ]

        #expect(set.count == 3)
    }
}
