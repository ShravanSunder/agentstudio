import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DropTargetResolverTests {
    private let paneA = UUID()
    private let paneB = UUID()
    private let paneC = UUID()

    private var threePaneSingleRow:
        (
            rows: [RowID: [UUID]],
            frames: [UUID: CGRect],
            bounds: CGRect
        )
    {
        (
            rows: [.main: [paneA, paneB, paneC]],
            frames: [
                paneA: CGRect(x: 0, y: 0, width: 100, height: 200),
                paneB: CGRect(x: 100, y: 0, width: 100, height: 200),
                paneC: CGRect(x: 200, y: 0, width: 100, height: 200),
            ],
            bounds: CGRect(x: 0, y: 0, width: 300, height: 200)
        )
    }

    @Test
    func resolve_onPane_allowsPaneSplit_returnsPaneSplit_leftHalf() {
        let context = threePaneSingleRow

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 25, y: 100),
            rows: context.rows,
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .main,
            splittablePanes: [paneA, paneB, paneC]
        )

        #expect(target == .paneSplit(paneId: paneA, side: .left))
    }

    @Test
    func resolve_onPane_allowsPaneSplit_returnsPaneSplit_rightHalf() {
        let context = threePaneSingleRow

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 75, y: 100),
            rows: context.rows,
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .main,
            splittablePanes: [paneA, paneB, paneC]
        )

        #expect(target == .paneSplit(paneId: paneA, side: .right))
    }

    @Test
    func resolve_onPane_notSplittable_fallsThroughToPaneSlot() {
        let context = threePaneSingleRow

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 25, y: 100),
            rows: context.rows,
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .main,
            splittablePanes: [paneB, paneC]
        )

        #expect(target == .paneSlot(row: .main, index: 0))
    }

    @Test
    func resolve_configDisallowsPaneSplit_emitsSlotOnly() {
        let context = threePaneSingleRow

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 25, y: 100),
            rows: [.drawerTop: [paneA, paneB, paneC]],
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .drawerTwoRow,
            splittablePanes: [paneA, paneB, paneC]
        )

        #expect(target == .paneSlot(row: .drawerTop, index: 0))
    }

    @Test
    func resolve_betweenPanes_returnsPaneSlot() {
        let context = threePaneSingleRow

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 75, y: 100),
            rows: [.drawerTop: [paneA, paneB, paneC]],
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .drawerTwoRow,
            splittablePanes: []
        )

        #expect(target == .paneSlot(row: .drawerTop, index: 1))
    }

    @Test
    func resolve_outsideVertically_returnsNil() {
        let context = threePaneSingleRow

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 150, y: 500),
            rows: context.rows,
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .main,
            splittablePanes: [paneA, paneB, paneC]
        )

        #expect(target == nil)
    }

    @Test
    func resolve_emptyRow_returnsNil() {
        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 175, y: 100),
            rows: [.main: []],
            paneFrames: [:],
            containerBounds: CGRect(x: 0, y: 0, width: 300, height: 200),
            config: .main,
            splittablePanes: []
        )

        #expect(target == nil)
    }

    @Test
    func resolve_cursorInTopBand_drawerSingleRow_returnsNewRowTop() {
        let context = threePaneSingleRow

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 175, y: 14),
            rows: [.drawerTop: [paneA, paneB, paneC]],
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .drawerSingleRow,
            splittablePanes: []
        )

        #expect(target == .paneNewRow(position: .top))
    }

    @Test
    func resolve_cursorInBottomBand_drawerSingleRow_returnsNewRowBottom() {
        let context = threePaneSingleRow

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 150, y: 190),
            rows: [.drawerTop: [paneA, paneB, paneC]],
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .drawerSingleRow,
            splittablePanes: []
        )

        #expect(target == .paneNewRow(position: .bottom))
    }

    @Test
    func resolve_cursorInMiddle_drawerSingleRow_returnsSlot() {
        let context = threePaneSingleRow

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 175, y: 100),
            rows: [.drawerTop: [paneA, paneB, paneC]],
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .drawerSingleRow,
            splittablePanes: []
        )

        #expect(target == .paneSlot(row: .drawerTop, index: 2))
    }

    @Test
    func resolve_bandIgnored_whenConfigLacksNewRowBand() {
        let context = threePaneSingleRow

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 175, y: 14),
            rows: [.drawerTop: [paneA, paneB, paneC]],
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .drawerTwoRow,
            splittablePanes: []
        )

        #expect(target == .paneSlot(row: .drawerTop, index: 2))
    }

    @Test
    func resolve_twoRowDrawer_cursorInTopRow_returnsTopSlot() {
        let paneD = UUID()
        let frames: [UUID: CGRect] = [
            paneA: CGRect(x: 0, y: 0, width: 150, height: 100),
            paneB: CGRect(x: 150, y: 0, width: 150, height: 100),
            paneC: CGRect(x: 0, y: 100, width: 150, height: 100),
            paneD: CGRect(x: 150, y: 100, width: 150, height: 100),
        ]

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 75, y: 50),
            rows: [.drawerTop: [paneA, paneB], .drawerBottom: [paneC, paneD]],
            paneFrames: frames,
            containerBounds: CGRect(x: 0, y: 0, width: 300, height: 200),
            config: .drawerTwoRow,
            splittablePanes: []
        )

        #expect(target == .paneSlot(row: .drawerTop, index: 0))
    }

    @Test
    func resolve_twoRowDrawer_cursorInBottomRow_returnsBottomSlot() {
        let paneD = UUID()
        let frames: [UUID: CGRect] = [
            paneA: CGRect(x: 0, y: 0, width: 150, height: 100),
            paneB: CGRect(x: 150, y: 0, width: 150, height: 100),
            paneC: CGRect(x: 0, y: 100, width: 150, height: 100),
            paneD: CGRect(x: 150, y: 100, width: 150, height: 100),
        ]

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 260, y: 150),
            rows: [.drawerTop: [paneA, paneB], .drawerBottom: [paneC, paneD]],
            paneFrames: frames,
            containerBounds: CGRect(x: 0, y: 0, width: 300, height: 200),
            config: .drawerTwoRow,
            splittablePanes: []
        )

        #expect(target == .paneSlot(row: .drawerBottom, index: 2))
    }

    @Test
    func resolve_singleRowConfig_ignoresBottomRowEvenWhenRowsMapContainsOne() {
        let bottomPane = UUID()
        let frames: [UUID: CGRect] = [
            paneA: CGRect(x: 0, y: 0, width: 100, height: 100),
            bottomPane: CGRect(x: 0, y: 200, width: 100, height: 100),
        ]

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 50, y: 250),
            rows: [
                .drawerTop: [paneA],
                .drawerBottom: [bottomPane],
            ],
            paneFrames: frames,
            containerBounds: CGRect(x: 0, y: 0, width: 100, height: 300),
            config: .drawerSingleRow,
            splittablePanes: []
        )

        #expect(target == nil)
    }

    @Test
    func resolve_leftCorridor_main_returnsSlotZero() {
        let context = threePaneSingleRow
        let corridorBounds = CGRect(x: -24, y: 0, width: 324, height: 200)

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: -12, y: 100),
            rows: context.rows,
            paneFrames: context.frames,
            containerBounds: corridorBounds,
            config: .main,
            splittablePanes: Set(context.frames.keys)
        )

        #expect(target == .paneSlot(row: .main, index: 0))
    }

    @Test
    func resolve_rightCorridor_main_returnsTrailingSlot() {
        let context = threePaneSingleRow
        let corridorBounds = CGRect(x: 0, y: 0, width: 324, height: 200)

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 310, y: 100),
            rows: context.rows,
            paneFrames: context.frames,
            containerBounds: corridorBounds,
            config: .main,
            splittablePanes: Set(context.frames.keys)
        )

        #expect(target == .paneSlot(row: .main, index: 3))
    }

    @Test
    func resolve_corridorIgnored_whenConfigCorridorIsZero() {
        let context = threePaneSingleRow
        let corridorBounds = CGRect(x: -24, y: 0, width: 324, height: 200)

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: -12, y: 100),
            rows: [.drawerTop: [paneA, paneB, paneC]],
            paneFrames: context.frames,
            containerBounds: corridorBounds,
            config: .drawerSingleRow,
            splittablePanes: []
        )

        #expect(target == nil)
    }

    @Test
    func resolve_rightOfLastPaneWithinRowBand_returnsTrailingSlot() {
        let paneD = UUID()
        let frames: [UUID: CGRect] = [
            paneA: CGRect(x: 0, y: 0, width: 100, height: 60),
            paneB: CGRect(x: 110, y: 0, width: 100, height: 60),
            paneC: CGRect(x: 0, y: 80, width: 100, height: 60),
            paneD: CGRect(x: 110, y: 80, width: 100, height: 60),
        ]

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 215, y: 110),
            rows: [.drawerTop: [paneA, paneB], .drawerBottom: [paneC, paneD]],
            paneFrames: frames,
            containerBounds: CGRect(x: 0, y: 0, width: 220, height: 160),
            config: .drawerTwoRow,
            splittablePanes: []
        )

        #expect(target == .paneSlot(row: .drawerBottom, index: 2))
    }

    @Test
    func targetRects_singleRow_emitsSlotAndNewRowRects() {
        let context = threePaneSingleRow

        let rects = DropTargetResolver.targetRects(
            rows: [.drawerTop: [paneA, paneB, paneC]],
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .drawerSingleRow
        )

        #expect(rects.count == 6)
        #expect(rects[.paneNewRow(position: .top)] != nil)
        #expect(rects[.paneNewRow(position: .bottom)] != nil)
        #expect(rects[.paneSlot(row: .drawerTop, index: 0)] != nil)
        #expect(rects[.paneSlot(row: .drawerTop, index: 3)] != nil)
    }

    @Test
    func targetRects_main_emitsOnlySlotRects() {
        let context = threePaneSingleRow

        let rects = DropTargetResolver.targetRects(
            rows: context.rows,
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .main
        )

        #expect(rects.count == 4)
        #expect(rects[.paneNewRow(position: .top)] == nil)
    }

    @Test
    func resolveLatched_acceptsResolvedTarget() {
        let context = threePaneSingleRow

        let target = DropTargetResolver.resolveLatched(
            location: CGPoint(x: 75, y: 100),
            rows: context.rows,
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .main,
            splittablePanes: [],
            currentTarget: nil,
            shouldAccept: { _ in true }
        )

        #expect(target == .paneSlot(row: .main, index: 1))
    }

    @Test
    func resolveLatched_falseAcceptor_keepsCurrent() {
        let context = threePaneSingleRow
        let current: DropTarget = .paneSlot(row: .main, index: 2)

        let target = DropTargetResolver.resolveLatched(
            location: CGPoint(x: 75, y: 100),
            rows: context.rows,
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .main,
            splittablePanes: [],
            currentTarget: current,
            shouldAccept: { $0 == current }
        )

        #expect(target == current)
    }

    @Test
    func resolveLatched_falseAcceptor_noCurrent_returnsNil() {
        let context = threePaneSingleRow

        let target = DropTargetResolver.resolveLatched(
            location: CGPoint(x: 75, y: 100),
            rows: context.rows,
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .main,
            splittablePanes: [],
            currentTarget: nil,
            shouldAccept: { _ in false }
        )

        #expect(target == nil)
    }
}
