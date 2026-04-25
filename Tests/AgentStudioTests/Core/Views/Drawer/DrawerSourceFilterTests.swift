import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

/// Drawer source-aware filtering. The drawer reuses the universal rule
/// from `PaneDragCoordinatorSourceFilterTests` for in-row targets, plus
/// drawer-specific rules for the new-row band and the row-count cap.
///
/// In drawer terms, "source" is conveyed via `excludedPaneIds` on
/// `DrawerPaneDragGeometry`.
///
///   ▸ R7   in-row R1+R2 also apply (split-self + adjacent slots)
///   ▸ R8   solo row + band drop = no-op → reject
///   ▸ R13  drawer 1-row bands need ≥2 panes in the row
///   ▸ R14  drawer 2-row bands are absent (max rows = 2)
///   ▸ R15  cross-row drops in a 2-row drawer remain valid
///   ▸ R16  solo-row drag-out is allowed (drawer collapses to 1-row)
@Suite(.serialized)
struct DrawerSourceFilterTests {

    // MARK: - R7: in-row R1+R2 apply to drawer single row

    @Test
    func r7_singleRow_overSourceCenter_returnsNil() {
        // [P₁ S P₃] in single drawer row. S in middle.
        let p1 = UUID()
        let s = UUID()
        let p3 = UUID()
        let frames: [UUID: CGRect] = [
            p1: CGRect(x: 0, y: 40, width: 100, height: 80),
            s: CGRect(x: 110, y: 40, width: 100, height: 80),
            p3: CGRect(x: 220, y: 40, width: 100, height: 80),
        ]
        let cursor = CGPoint(x: 160, y: 80)  // S center

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: cursor,
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([p1, s, p3])),
                bounds: CGRect(x: 0, y: 0, width: 320, height: 140),
                excludedPaneIds: [s]
            )
        )

        #expect(target == nil)
    }

    @Test
    func r7_singleRow_overLeftAdjacentSlot_returnsNil() {
        // S at index 1; right 1/4 of P₁ → slot 1 (= position i, adjacent).
        let p1 = UUID()
        let s = UUID()
        let p3 = UUID()
        let frames: [UUID: CGRect] = [
            p1: CGRect(x: 0, y: 40, width: 100, height: 80),
            s: CGRect(x: 110, y: 40, width: 100, height: 80),
            p3: CGRect(x: 220, y: 40, width: 100, height: 80),
        ]
        let cursor = CGPoint(x: 95, y: 80)  // P₁ right 1/4

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: cursor,
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([p1, s, p3])),
                bounds: CGRect(x: 0, y: 0, width: 320, height: 140),
                excludedPaneIds: [s]
            )
        )

        #expect(target == nil)
    }

    @Test
    func r7_singleRow_overRightAdjacentSlot_returnsNil() {
        // S at index 1; left 1/4 of P₃ → slot 2 (= position i+1, adjacent).
        let p1 = UUID()
        let s = UUID()
        let p3 = UUID()
        let frames: [UUID: CGRect] = [
            p1: CGRect(x: 0, y: 40, width: 100, height: 80),
            s: CGRect(x: 110, y: 40, width: 100, height: 80),
            p3: CGRect(x: 220, y: 40, width: 100, height: 80),
        ]
        let cursor = CGPoint(x: 225, y: 80)  // P₃ left 1/4

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: cursor,
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([p1, s, p3])),
                bounds: CGRect(x: 0, y: 0, width: 320, height: 140),
                excludedPaneIds: [s]
            )
        )

        #expect(target == nil)
    }

    @Test
    func r7_singleRow_overForeignSplit_returnsTarget() {
        // S at index 1; cursor in P₃ left half center → split(P₃, .left).
        let p1 = UUID()
        let s = UUID()
        let p3 = UUID()
        let frames: [UUID: CGRect] = [
            p1: CGRect(x: 0, y: 40, width: 100, height: 80),
            s: CGRect(x: 110, y: 40, width: 100, height: 80),
            p3: CGRect(x: 220, y: 40, width: 100, height: 80),
        ]
        let cursor = CGPoint(x: 260, y: 80)  // P₃ center, left of midX (270)

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: cursor,
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([p1, s, p3])),
                bounds: CGRect(x: 0, y: 0, width: 320, height: 140),
                excludedPaneIds: [s]
            )
        )

        #expect(target == .paneSplit(paneId: p3, side: .left))
    }

    @Test
    func r7_singleRow_visualsOmitSourceAndAdjacentSlots() {
        // S in middle; visuals dict must omit split(S) + slot 1 + slot 2.
        let p1 = UUID()
        let s = UUID()
        let p3 = UUID()
        let frames: [UUID: CGRect] = [
            p1: CGRect(x: 0, y: 40, width: 100, height: 80),
            s: CGRect(x: 110, y: 40, width: 100, height: 80),
            p3: CGRect(x: 220, y: 40, width: 100, height: 80),
        ]

        let visuals = DrawerPaneDragCoordinator.targetVisuals(
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([p1, s, p3])),
                bounds: CGRect(x: 0, y: 0, width: 320, height: 140),
                excludedPaneIds: [s]
            )
        )

        #expect(visuals[.paneSplit(paneId: s, side: .left)] == nil)
        #expect(visuals[.paneSplit(paneId: s, side: .right)] == nil)
        #expect(visuals[.rowSlot(row: .top, insertionIndex: 1)] == nil)
        #expect(visuals[.rowSlot(row: .top, insertionIndex: 2)] == nil)
        #expect(visuals[.paneSplit(paneId: p1, side: .left)] != nil)
        #expect(visuals[.paneSplit(paneId: p3, side: .right)] != nil)
        #expect(visuals[.rowSlot(row: .top, insertionIndex: 0)] != nil)
        #expect(visuals[.rowSlot(row: .top, insertionIndex: 3)] != nil)
    }

    // MARK: - R8 / R13a: solo row → no band targets

    @Test
    func r13a_singleRowSoloSource_topBand_returnsNil() {
        // [S] in single row. Dropping in any band creates a row containing
        // only S, leaves original row empty (collapses) — net no-op.
        let s = UUID()
        let frames: [UUID: CGRect] = [s: CGRect(x: 20, y: 40, width: 100, height: 80)]
        let cursorTopBand = CGPoint(x: 70, y: 10)

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: cursorTopBand,
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([s])),
                bounds: CGRect(x: 0, y: 0, width: 200, height: 140),
                excludedPaneIds: [s]
            )
        )

        #expect(target == nil)
    }

    @Test
    func r13a_singleRowSoloSource_bottomBand_returnsNil() {
        let s = UUID()
        let frames: [UUID: CGRect] = [s: CGRect(x: 20, y: 40, width: 100, height: 80)]
        let cursorBottomBand = CGPoint(x: 70, y: 130)

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: cursorBottomBand,
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([s])),
                bounds: CGRect(x: 0, y: 0, width: 200, height: 140),
                excludedPaneIds: [s]
            )
        )

        #expect(target == nil)
    }

    @Test
    func r13a_singleRowSoloSource_visualsHaveNoBandTargets() {
        let s = UUID()
        let frames: [UUID: CGRect] = [s: CGRect(x: 20, y: 40, width: 100, height: 80)]

        let visuals = DrawerPaneDragCoordinator.targetVisuals(
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([s])),
                bounds: CGRect(x: 0, y: 0, width: 200, height: 140),
                excludedPaneIds: [s]
            )
        )

        #expect(visuals[.createSecondRow(position: .top)] == nil)
        #expect(visuals[.createSecondRow(position: .bottom)] == nil)
    }

    // MARK: - R13b: 1-row with sibling → bands valid

    @Test
    func r13b_singleRowWithSibling_topBand_returnsTarget() {
        // [S P_other] — dropping S in top band creates [T: S][B: P_other].
        let s = UUID()
        let other = UUID()
        let frames: [UUID: CGRect] = [
            s: CGRect(x: 0, y: 40, width: 100, height: 80),
            other: CGRect(x: 110, y: 40, width: 100, height: 80),
        ]
        let cursorTopBand = CGPoint(x: 100, y: 10)

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: cursorTopBand,
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([s, other])),
                bounds: CGRect(x: 0, y: 0, width: 220, height: 140),
                excludedPaneIds: [s]
            )
        )

        #expect(target == .createSecondRow(position: .top))
    }

    @Test
    func r13b_singleRowWithSibling_bottomBand_returnsTarget() {
        let s = UUID()
        let other = UUID()
        let frames: [UUID: CGRect] = [
            s: CGRect(x: 0, y: 40, width: 100, height: 80),
            other: CGRect(x: 110, y: 40, width: 100, height: 80),
        ]
        let cursorBottomBand = CGPoint(x: 100, y: 130)

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: cursorBottomBand,
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([s, other])),
                bounds: CGRect(x: 0, y: 0, width: 220, height: 140),
                excludedPaneIds: [s]
            )
        )

        #expect(target == .createSecondRow(position: .bottom))
    }

    // MARK: - R14: 2-row drawer never has band targets

    @Test
    func r14_twoRow_visualsHaveNoBandTargets() {
        // 2-row drawer at max rows. Bands must not appear.
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let frames: [UUID: CGRect] = [
            a: CGRect(x: 0, y: 0, width: 100, height: 60),
            b: CGRect(x: 110, y: 0, width: 100, height: 60),
            c: CGRect(x: 0, y: 80, width: 100, height: 60),
        ]

        let visuals = DrawerPaneDragCoordinator.targetVisuals(
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(
                    topRow: Layout.autoTiled([a, b]),
                    bottomRow: Layout.autoTiled([c]),
                    rowSplitRatio: 0.5
                ),
                bounds: CGRect(x: 0, y: 0, width: 220, height: 140),
                excludedPaneIds: [a]
            )
        )

        #expect(visuals[.createSecondRow(position: .top)] == nil)
        #expect(visuals[.createSecondRow(position: .bottom)] == nil)
    }

    // MARK: - R15: cross-row drops in 2-row drawer are foreign-valid

    @Test
    func r15_twoRow_overOtherRowSplit_returnsForeignSplitTarget() {
        // S in top row; cursor over bottom-row pane center → foreign split valid.
        let s = UUID()
        let topB = UUID()
        let bottomA = UUID()
        let frames: [UUID: CGRect] = [
            s: CGRect(x: 0, y: 0, width: 100, height: 60),
            topB: CGRect(x: 110, y: 0, width: 100, height: 60),
            bottomA: CGRect(x: 0, y: 80, width: 200, height: 60),
        ]
        let cursorOverBottomLeftHalf = CGPoint(x: 60, y: 110)  // bottomA center, left of midX (100)

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: cursorOverBottomLeftHalf,
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(
                    topRow: Layout.autoTiled([s, topB]),
                    bottomRow: Layout.autoTiled([bottomA]),
                    rowSplitRatio: 0.5
                ),
                bounds: CGRect(x: 0, y: 0, width: 220, height: 140),
                excludedPaneIds: [s]
            )
        )

        #expect(target == .paneSplit(paneId: bottomA, side: .left))
    }

    @Test
    func r15_twoRow_overOtherRowSlot_returnsForeignSlotTarget() {
        // S in top row; cursor in bottom row's left edge → bottom slot 0.
        let s = UUID()
        let topB = UUID()
        let bottomA = UUID()
        let bottomB = UUID()
        let frames: [UUID: CGRect] = [
            s: CGRect(x: 0, y: 0, width: 100, height: 60),
            topB: CGRect(x: 110, y: 0, width: 100, height: 60),
            bottomA: CGRect(x: 0, y: 80, width: 100, height: 60),
            bottomB: CGRect(x: 110, y: 80, width: 100, height: 60),
        ]
        // cursor at (95, 110) → in bottomA's right 1/4 → slot 1 (between bottoms)
        let cursorOverBottomSlot = CGPoint(x: 95, y: 110)

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: cursorOverBottomSlot,
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(
                    topRow: Layout.autoTiled([s, topB]),
                    bottomRow: Layout.autoTiled([bottomA, bottomB]),
                    rowSplitRatio: 0.5
                ),
                bounds: CGRect(x: 0, y: 0, width: 220, height: 140),
                excludedPaneIds: [s]
            )
        )

        #expect(target == .rowSlot(row: .bottom, insertionIndex: 1))
    }

    // MARK: - R16: solo-row drag-out resolves the foreign target

    @Test
    func r16_twoRow_soloSourceRowDragToOtherRow_resolvesForeignTarget() {
        // [T: S][B: B₁ B₂]. S alone in top row. Cursor over B₁ center →
        // foreign split. Resolver accepts; downstream apply path handles
        // the row-collapse to 1-row drawer.
        let s = UUID()
        let b1 = UUID()
        let b2 = UUID()
        let frames: [UUID: CGRect] = [
            s: CGRect(x: 0, y: 0, width: 200, height: 60),
            b1: CGRect(x: 0, y: 80, width: 100, height: 60),
            b2: CGRect(x: 110, y: 80, width: 100, height: 60),
        ]
        let cursorOverB1Center = CGPoint(x: 40, y: 110)  // B₁ center, left of midX (50)

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: cursorOverB1Center,
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(
                    topRow: Layout.autoTiled([s]),
                    bottomRow: Layout.autoTiled([b1, b2]),
                    rowSplitRatio: 0.5
                ),
                bounds: CGRect(x: 0, y: 0, width: 220, height: 140),
                excludedPaneIds: [s]
            )
        )

        #expect(target == .paneSplit(paneId: b1, side: .left))
    }

    @Test
    func r16_twoRow_soloSourceRow_inRowTargetsAllRejected() {
        // [T: S][B: B₁]. Even though S has no in-row siblings, its own
        // row's slots and split are still rejected (R1+R2 = self only
        // when alone). Cursor over S anywhere → nil.
        let s = UUID()
        let b1 = UUID()
        let frames: [UUID: CGRect] = [
            s: CGRect(x: 0, y: 0, width: 200, height: 60),
            b1: CGRect(x: 0, y: 80, width: 200, height: 60),
        ]
        let cursorOnSourceCenter = CGPoint(x: 100, y: 30)  // S center

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: cursorOnSourceCenter,
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(
                    topRow: Layout.autoTiled([s]),
                    bottomRow: Layout.autoTiled([b1]),
                    rowSplitRatio: 0.5
                ),
                bounds: CGRect(x: 0, y: 0, width: 220, height: 140),
                excludedPaneIds: [s]
            )
        )

        #expect(target == nil)
    }

    // MARK: - Helpers

    private func geometry(
        paneFrames: [UUID: CGRect],
        layout: DrawerGridLayout,
        bounds: CGRect,
        minimizedPaneIds: Set<UUID> = [],
        excludedPaneIds: Set<UUID> = []
    ) -> DrawerPaneDragGeometry {
        DrawerPaneDragGeometry(
            paneFrames: paneFrames,
            layout: layout,
            containerBounds: bounds,
            minimizedPaneIds: minimizedPaneIds,
            excludedPaneIds: excludedPaneIds
        )
    }
}
