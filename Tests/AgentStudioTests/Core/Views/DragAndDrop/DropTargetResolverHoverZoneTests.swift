import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

/// Pin the 1/4 + 1/2 + 1/4 hover-zone behavior the resolver should
/// produce for `.main` (and any single-row config). These tests are
/// the user-facing contract: split happens only in center 1/2;
/// boundary 1/4 zones produce between-slot targets; outer 1/4 of
/// edge panes produce edge-insert slot targets.
@Suite(.serialized)
struct DropTargetResolverHoverZoneTests {
    private let paneA = UUID()
    private let paneB = UUID()
    private let paneC = UUID()

    /// Three 100-wide panes laid out across a 300-wide row.
    /// Side-zone floor is 24, natural quarter is 25, so the zones are:
    ///
    ///     paneA  [0..25)  left  / [25..75) center / [75..100)  right
    ///     paneB  [100..125) left / [125..175) center / [175..200) right
    ///     paneC  [200..225) left / [225..275) center / [275..300] right
    private var threePaneRow: (rows: [RowID: [UUID]], frames: [UUID: CGRect], bounds: CGRect) {
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

    private var allSplittable: Set<UUID> { [paneA, paneB, paneC] }

    // MARK: - Center 1/2 → split

    @Test
    func centerZoneOfSplittablePane_returnsSplitWithSideByMidX() {
        let context = threePaneRow

        let leftHalf = DropTargetResolver.resolve(
            location: CGPoint(x: 40, y: 100),  // pane A center, left of midX (50)
            rows: context.rows,
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .main,
            splittablePanes: allSplittable
        )
        #expect(leftHalf == .paneSplit(paneId: paneA, side: .left))

        let rightHalf = DropTargetResolver.resolve(
            location: CGPoint(x: 60, y: 100),  // pane A center, right of midX
            rows: context.rows,
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .main,
            splittablePanes: allSplittable
        )
        #expect(rightHalf == .paneSplit(paneId: paneA, side: .right))
    }

    // MARK: - Edge 1/4 of edge pane → edge-insert slot

    @Test
    func leftQuarterOfLeftmostPane_returnsSlotZero() {
        let context = threePaneRow

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 10, y: 100),  // pane A left zone
            rows: context.rows,
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .main,
            splittablePanes: allSplittable
        )

        #expect(target == .paneSlot(row: .main, index: 0))
    }

    @Test
    func rightQuarterOfRightmostPane_returnsTrailingSlot() {
        let context = threePaneRow

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 290, y: 100),  // pane C right zone
            rows: context.rows,
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .main,
            splittablePanes: allSplittable
        )

        #expect(target == .paneSlot(row: .main, index: 3))
    }

    // MARK: - Boundary 1/4 zones → between slot

    @Test
    func rightQuarterOfMiddlePane_returnsBetweenWithRightNeighbor() {
        let context = threePaneRow

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 180, y: 100),  // pane B right zone
            rows: context.rows,
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .main,
            splittablePanes: allSplittable
        )

        #expect(target == .paneSlot(row: .main, index: 2))
    }

    @Test
    func leftQuarterOfMiddlePane_returnsBetweenWithLeftNeighbor() {
        let context = threePaneRow

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 110, y: 100),  // pane B left zone
            rows: context.rows,
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .main,
            splittablePanes: allSplittable
        )

        #expect(target == .paneSlot(row: .main, index: 1))
    }

    @Test
    func rightQuarterOfLeftmostPane_returnsBetweenWithRightNeighbor() {
        let context = threePaneRow

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 90, y: 100),  // pane A right zone
            rows: context.rows,
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .main,
            splittablePanes: allSplittable
        )

        #expect(target == .paneSlot(row: .main, index: 1))
    }

    @Test
    func leftQuarterOfRightmostPane_returnsBetweenWithLeftNeighbor() {
        let context = threePaneRow

        let target = DropTargetResolver.resolve(
            location: CGPoint(x: 210, y: 100),  // pane C left zone
            rows: context.rows,
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .main,
            splittablePanes: allSplittable
        )

        #expect(target == .paneSlot(row: .main, index: 2))
    }

    // MARK: - Non-splittable pane: center falls through to slot

    @Test
    func centerZoneOfNonSplittablePane_fallsThroughToSlot() {
        let context = threePaneRow

        let leftSide = DropTargetResolver.resolve(
            location: CGPoint(x: 40, y: 100),  // paneA center, left of midX
            rows: context.rows,
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .main,
            splittablePanes: [paneB, paneC]  // paneA NOT splittable
        )
        #expect(leftSide == .paneSlot(row: .main, index: 0))

        let rightSide = DropTargetResolver.resolve(
            location: CGPoint(x: 60, y: 100),  // paneA center, right of midX
            rows: context.rows,
            paneFrames: context.frames,
            containerBounds: context.bounds,
            config: .main,
            splittablePanes: [paneB, paneC]
        )
        #expect(rightSide == .paneSlot(row: .main, index: 1))
    }

    // MARK: - Single pane (no neighbors)

    @Test
    func singlePane_centerSplits_edgesInsertAdjacent() {
        let onlyPane = paneA
        let frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        let rows: [RowID: [UUID]] = [.main: [onlyPane]]
        let frames: [UUID: CGRect] = [onlyPane: frame]
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)

        let leftEdge = DropTargetResolver.resolve(
            location: CGPoint(x: 10, y: 50),
            rows: rows,
            paneFrames: frames,
            containerBounds: bounds,
            config: .main,
            splittablePanes: [onlyPane]
        )
        #expect(leftEdge == .paneSlot(row: .main, index: 0))

        let center = DropTargetResolver.resolve(
            location: CGPoint(x: 100, y: 50),
            rows: rows,
            paneFrames: frames,
            containerBounds: bounds,
            config: .main,
            splittablePanes: [onlyPane]
        )
        // x=100 = midX → side .right (resolver uses < midX for left)
        #expect(center == .paneSplit(paneId: onlyPane, side: .right))

        let rightEdge = DropTargetResolver.resolve(
            location: CGPoint(x: 190, y: 50),
            rows: rows,
            paneFrames: frames,
            containerBounds: bounds,
            config: .main,
            splittablePanes: [onlyPane]
        )
        #expect(rightEdge == .paneSlot(row: .main, index: 1))
    }
}
