import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

/// Source-aware filtering on `PaneDragCoordinator`.
///
/// Universal rule for source S at index i in the row:
///   reject  split(S)            (R1 — split-self)
///   reject  slot i               (R2 — position immediately before S)
///   reject  slot i+1             (R2 — position immediately after S)
///
/// All other targets stay valid (R3 — foreign).
///
/// Visuals dict mirrors resolver decisions (R4 — overlay can never paint
/// a target the commit path would reject).
///
/// Single-pane row produces no valid targets (R6 — empty visuals).
///
/// Source pane not in the coordinator's paneFrames → returns nil
/// (R17 — defensive cross-container guard).
///
/// Minimized neighbor composes with source filtering (R10).
///
/// Pane-count generalizations: 2-pane (R11) and N-pane (R12) matrices.
@Suite(.serialized)
struct PaneDragCoordinatorSourceFilterTests {

    // MARK: - R1: split(S) is never a valid target

    @Test
    func r1_resolve_overSourceCenter_returnsNil() {
        let setup = ThreePaneRow.make()
        let cursorOnSourceCenter = CGPoint(x: setup.frames[setup.p2]!.midX, y: 50)

        let target = PaneDragCoordinator.resolveTarget(
            location: cursorOnSourceCenter,
            paneFrames: setup.frames,
            containerBounds: setup.bounds,
            minimizedPaneIds: [],
            sourcePaneId: setup.p2
        )

        #expect(target == nil)
    }

    @Test
    func r1_visuals_omitSelfSplits() {
        let setup = ThreePaneRow.make()

        let visuals = PaneDragCoordinator.targetVisuals(
            paneFrames: setup.frames,
            containerBounds: setup.bounds,
            minimizedPaneIds: [],
            sourcePaneId: setup.p2
        )

        #expect(visuals[.paneSplit(paneId: setup.p2, side: .left)] == nil)
        #expect(visuals[.paneSplit(paneId: setup.p2, side: .right)] == nil)
        #expect(visuals[.paneSplit(paneId: setup.p1, side: .left)] != nil)
        #expect(visuals[.paneSplit(paneId: setup.p1, side: .right)] != nil)
        #expect(visuals[.paneSplit(paneId: setup.p3, side: .left)] != nil)
        #expect(visuals[.paneSplit(paneId: setup.p3, side: .right)] != nil)
    }

    // MARK: - R2: slot i and slot i+1 are never valid targets

    @Test
    func r2_overLeftAdjacentSlotOfForeignSibling_promotesToSiblingSplit() throws {
        // S = P₂ (index 1). Cursor in right 1/4 of P₁ would resolve to
        // slot 1 (adjacent to S). With the sibling-promotion exception,
        // it commits as split(P₁, .right) instead — the user gets
        // commit feedback over the sibling's edge instead of a dead zone.
        let setup = ThreePaneRow.make()
        let p1Frame = setup.frames[setup.p1]!
        let cursor = CGPoint(x: p1Frame.maxX - 5, y: 50)

        let target = try #require(
            PaneDragCoordinator.resolveTarget(
                location: cursor,
                paneFrames: setup.frames,
                containerBounds: setup.bounds,
                minimizedPaneIds: [],
                sourcePaneId: setup.p2
            )
        )

        #expect(target.sizingTarget == .paneSplit(paneId: setup.p1, side: .right))
    }

    @Test
    func r2_overRightAdjacentSlotOfForeignSibling_promotesToSiblingSplit() throws {
        // S = P₂. Cursor in left 1/4 of P₃ would resolve to slot 2.
        // Promotes to split(P₃, .left).
        let setup = ThreePaneRow.make()
        let p3Frame = setup.frames[setup.p3]!
        let cursor = CGPoint(x: p3Frame.minX + 5, y: 50)

        let target = try #require(
            PaneDragCoordinator.resolveTarget(
                location: cursor,
                paneFrames: setup.frames,
                containerBounds: setup.bounds,
                minimizedPaneIds: [],
                sourcePaneId: setup.p2
            )
        )

        #expect(target.sizingTarget == .paneSplit(paneId: setup.p3, side: .left))
    }

    @Test
    func r2_overSourcePaneOwnQuarterZone_returnsNil() {
        // Cursor in right 1/4 of S itself — promotion can't apply
        // because the containing pane IS source. Stays a dead zone.
        let setup = ThreePaneRow.make()
        let sourceFrame = setup.frames[setup.p2]!
        let cursorOnSourceRightQuarter = CGPoint(x: sourceFrame.maxX - 5, y: 50)

        let target = PaneDragCoordinator.resolveTarget(
            location: cursorOnSourceRightQuarter,
            paneFrames: setup.frames,
            containerBounds: setup.bounds,
            minimizedPaneIds: [],
            sourcePaneId: setup.p2
        )

        #expect(target == nil)
    }

    @Test
    func r2_visuals_omitAdjacentSlots() {
        // S = P₂ at index 1 → adjacent slots are 1 and 2.
        let setup = ThreePaneRow.make()

        let visuals = PaneDragCoordinator.targetVisuals(
            paneFrames: setup.frames,
            containerBounds: setup.bounds,
            minimizedPaneIds: [],
            sourcePaneId: setup.p2
        )

        #expect(visuals[.paneSlot(row: .main, index: 1)] == nil)
        #expect(visuals[.paneSlot(row: .main, index: 2)] == nil)
        #expect(visuals[.paneSlot(row: .main, index: 0)] != nil)
        #expect(visuals[.paneSlot(row: .main, index: 3)] != nil)
    }

    // MARK: - R3: foreign targets stay valid

    @Test
    func r3_resolve_overForeignSplit_returnsTarget() throws {
        // S = P₂. Cursor in P₃ left half center → split(P₃, .left).
        let setup = ThreePaneRow.make()
        let p3Frame = setup.frames[setup.p3]!
        let cursor = CGPoint(x: p3Frame.midX - 5, y: 50)

        let target = try #require(
            PaneDragCoordinator.resolveTarget(
                location: cursor,
                paneFrames: setup.frames,
                containerBounds: setup.bounds,
                minimizedPaneIds: [],
                sourcePaneId: setup.p2
            )
        )

        #expect(target.sizingTarget == .paneSplit(paneId: setup.p3, side: .left))
    }

    @Test
    func r3_resolve_overFarSlot_returnsTarget() throws {
        // S = P₂. Cursor in left edge corridor → slot 0 (foreign).
        let setup = ThreePaneRow.make()
        let cursor = CGPoint(x: setup.bounds.minX + 2, y: 50)

        let target = try #require(
            PaneDragCoordinator.resolveTarget(
                location: cursor,
                paneFrames: setup.frames,
                containerBounds: setup.bounds,
                minimizedPaneIds: [],
                sourcePaneId: setup.p2
            )
        )

        // slot 0 sits before P₁; coordinator translates to leftmost-pane left zone.
        #expect(target.zone == .left)
        #expect(target.paneId == setup.p1)
    }

    // MARK: - R4: visuals dict mirrors resolver decisions

    @Test
    func r4_everyResolvedTarget_hasMatchingVisualEntry() throws {
        let setup = ThreePaneRow.make()
        let visuals = PaneDragCoordinator.targetVisuals(
            paneFrames: setup.frames,
            containerBounds: setup.bounds,
            minimizedPaneIds: [],
            sourcePaneId: setup.p2
        )

        // Sample the valid zones and verify each resolves AND has a visual.
        let validCursors: [CGPoint] = [
            CGPoint(x: setup.frames[setup.p1]!.midX - 5, y: 50),  // split P₁ left
            CGPoint(x: setup.frames[setup.p1]!.midX + 5, y: 50),  // split P₁ right
            CGPoint(x: setup.frames[setup.p3]!.midX - 5, y: 50),  // split P₃ left
            CGPoint(x: setup.frames[setup.p3]!.midX + 5, y: 50),  // split P₃ right
        ]

        for cursor in validCursors {
            let target = try #require(
                PaneDragCoordinator.resolveTarget(
                    location: cursor,
                    paneFrames: setup.frames,
                    containerBounds: setup.bounds,
                    minimizedPaneIds: [],
                    sourcePaneId: setup.p2
                ),
                "expected resolved target at \(cursor)"
            )
            #expect(
                visuals[target.sizingTarget] != nil,
                "missing visual entry for \(target.sizingTarget) at \(cursor)"
            )
        }
    }

    @Test
    func r4_rejectedZones_haveNoVisualEntry() {
        // Rejected zones for S = P₂: split(P₂, *), slot 1, slot 2.
        let setup = ThreePaneRow.make()
        let visuals = PaneDragCoordinator.targetVisuals(
            paneFrames: setup.frames,
            containerBounds: setup.bounds,
            minimizedPaneIds: [],
            sourcePaneId: setup.p2
        )

        #expect(visuals[.paneSplit(paneId: setup.p2, side: .left)] == nil)
        #expect(visuals[.paneSplit(paneId: setup.p2, side: .right)] == nil)
        #expect(visuals[.paneSlot(row: .main, index: 1)] == nil)
        #expect(visuals[.paneSlot(row: .main, index: 2)] == nil)
    }

    // MARK: - R6: single-pane row has no valid targets

    @Test
    func r6_singlePaneRow_resolveReturnsNilEverywhere() {
        let s = UUID()
        let frames: [UUID: CGRect] = [s: CGRect(x: 0, y: 0, width: 200, height: 100)]
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        let cursors = [
            CGPoint(x: 5, y: 50),  // left 1/4
            CGPoint(x: 100, y: 50),  // center
            CGPoint(x: 195, y: 50),  // right 1/4
        ]

        for cursor in cursors {
            let target = PaneDragCoordinator.resolveTarget(
                location: cursor,
                paneFrames: frames,
                containerBounds: bounds,
                minimizedPaneIds: [],
                sourcePaneId: s
            )
            #expect(target == nil, "expected nil at \(cursor); got \(String(describing: target))")
        }
    }

    @Test
    func r6_singlePaneRow_targetVisualsIsEmpty() {
        let s = UUID()
        let frames: [UUID: CGRect] = [s: CGRect(x: 0, y: 0, width: 200, height: 100)]
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)

        let visuals = PaneDragCoordinator.targetVisuals(
            paneFrames: frames,
            containerBounds: bounds,
            minimizedPaneIds: [],
            sourcePaneId: s
        )

        #expect(visuals.isEmpty)
    }

    // MARK: - R10: minimized neighbor composes with source filter

    @Test
    func r10_minimizedNeighborSplitFilter_composesWithSlotRejection() {
        // [P₁ P₂(min) S]. Source = S at index 2.
        // Cursor over P₂ center → would normally be split(P₂); but P₂
        // is minimized so split is filtered by the resolver's
        // splittablePanes, falling back to a slot. That slot is slot 2
        // (between P₂ and S), which is adjacent to S → R2 rejects it.
        let p1 = UUID()
        let p2 = UUID()
        let s = UUID()
        let frames: [UUID: CGRect] = [
            p1: CGRect(x: 0, y: 0, width: 100, height: 100),
            p2: CGRect(x: 100, y: 0, width: 100, height: 100),
            s: CGRect(x: 200, y: 0, width: 100, height: 100),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 100)
        let cursor = CGPoint(x: 160, y: 50)  // P₂ center, right of midX

        let target = PaneDragCoordinator.resolveTarget(
            location: cursor,
            paneFrames: frames,
            containerBounds: bounds,
            minimizedPaneIds: [p2],
            sourcePaneId: s
        )

        // Either: split(P₂) filtered by minimized → falls through to slot 2;
        // slot 2 rejected by R2 → nil.
        // Or: split(P₂) filtered by minimized → falls through to slot 1
        // (left of midX). Slot 1 is also valid (not adjacent to S=index 2).
        // We pick the right-of-midX cursor so slot is 2 (adjacent → rejected).
        #expect(target == nil)
    }

    // MARK: - R11: 2-pane row exact-validity matrix

    @Test
    func r11_twoPaneRow_sourceIsFirst_onlyForeignTargetsValid() {
        // [S P_other]. S = first. Valid: split(P_other, .left|.right), slot 2.
        let s = UUID()
        let other = UUID()
        let frames: [UUID: CGRect] = [
            s: CGRect(x: 0, y: 0, width: 100, height: 100),
            other: CGRect(x: 100, y: 0, width: 100, height: 100),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)

        let visuals = PaneDragCoordinator.targetVisuals(
            paneFrames: frames,
            containerBounds: bounds,
            minimizedPaneIds: [],
            sourcePaneId: s
        )

        // Rejected: split(S, *), slot 0, slot 1.
        #expect(visuals[.paneSplit(paneId: s, side: .left)] == nil)
        #expect(visuals[.paneSplit(paneId: s, side: .right)] == nil)
        #expect(visuals[.paneSlot(row: .main, index: 0)] == nil)
        #expect(visuals[.paneSlot(row: .main, index: 1)] == nil)
        // Accepted: split(other, *), slot 2.
        #expect(visuals[.paneSplit(paneId: other, side: .left)] != nil)
        #expect(visuals[.paneSplit(paneId: other, side: .right)] != nil)
        #expect(visuals[.paneSlot(row: .main, index: 2)] != nil)
    }

    @Test
    func r11_twoPaneRow_sourceIsSecond_onlyForeignTargetsValid() {
        // [P_other S]. S = second.
        let other = UUID()
        let s = UUID()
        let frames: [UUID: CGRect] = [
            other: CGRect(x: 0, y: 0, width: 100, height: 100),
            s: CGRect(x: 100, y: 0, width: 100, height: 100),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)

        let visuals = PaneDragCoordinator.targetVisuals(
            paneFrames: frames,
            containerBounds: bounds,
            minimizedPaneIds: [],
            sourcePaneId: s
        )

        // Rejected: split(S, *), slot 1, slot 2.
        #expect(visuals[.paneSplit(paneId: s, side: .left)] == nil)
        #expect(visuals[.paneSplit(paneId: s, side: .right)] == nil)
        #expect(visuals[.paneSlot(row: .main, index: 1)] == nil)
        #expect(visuals[.paneSlot(row: .main, index: 2)] == nil)
        // Accepted: split(other, *), slot 0.
        #expect(visuals[.paneSplit(paneId: other, side: .left)] != nil)
        #expect(visuals[.paneSplit(paneId: other, side: .right)] != nil)
        #expect(visuals[.paneSlot(row: .main, index: 0)] != nil)
    }

    // MARK: - R12: 4-pane row dead-window pattern

    @Test
    func r12_fourPaneRow_middleSource_hasThreeRejectedEntries() {
        // [P₁ S P₃ P₄]. S at index 1. Rejected: split(S), slot 1, slot 2.
        let p1 = UUID()
        let s = UUID()
        let p3 = UUID()
        let p4 = UUID()
        let frames: [UUID: CGRect] = [
            p1: CGRect(x: 0, y: 0, width: 100, height: 100),
            s: CGRect(x: 100, y: 0, width: 100, height: 100),
            p3: CGRect(x: 200, y: 0, width: 100, height: 100),
            p4: CGRect(x: 300, y: 0, width: 100, height: 100),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 100)

        let visuals = PaneDragCoordinator.targetVisuals(
            paneFrames: frames,
            containerBounds: bounds,
            minimizedPaneIds: [],
            sourcePaneId: s
        )

        // Rejected (3 entries split across slots and split):
        #expect(visuals[.paneSplit(paneId: s, side: .left)] == nil)
        #expect(visuals[.paneSplit(paneId: s, side: .right)] == nil)
        #expect(visuals[.paneSlot(row: .main, index: 1)] == nil)
        #expect(visuals[.paneSlot(row: .main, index: 2)] == nil)
        // Accepted: split(P₁), split(P₃), split(P₄), slot 0, slot 3, slot 4.
        #expect(visuals[.paneSplit(paneId: p1, side: .left)] != nil)
        #expect(visuals[.paneSplit(paneId: p3, side: .left)] != nil)
        #expect(visuals[.paneSplit(paneId: p4, side: .left)] != nil)
        #expect(visuals[.paneSlot(row: .main, index: 0)] != nil)
        #expect(visuals[.paneSlot(row: .main, index: 3)] != nil)
        #expect(visuals[.paneSlot(row: .main, index: 4)] != nil)
    }

    @Test
    func r12_fourPaneRow_lastSource_lastTwoSlotsAndSelfSplitRejected() {
        // [P₁ P₂ P₃ S]. S at index 3. Rejected: split(S), slot 3, slot 4.
        let p1 = UUID()
        let p2 = UUID()
        let p3 = UUID()
        let s = UUID()
        let frames: [UUID: CGRect] = [
            p1: CGRect(x: 0, y: 0, width: 100, height: 100),
            p2: CGRect(x: 100, y: 0, width: 100, height: 100),
            p3: CGRect(x: 200, y: 0, width: 100, height: 100),
            s: CGRect(x: 300, y: 0, width: 100, height: 100),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 100)

        let visuals = PaneDragCoordinator.targetVisuals(
            paneFrames: frames,
            containerBounds: bounds,
            minimizedPaneIds: [],
            sourcePaneId: s
        )

        #expect(visuals[.paneSplit(paneId: s, side: .left)] == nil)
        #expect(visuals[.paneSplit(paneId: s, side: .right)] == nil)
        #expect(visuals[.paneSlot(row: .main, index: 3)] == nil)
        #expect(visuals[.paneSlot(row: .main, index: 4)] == nil)
        #expect(visuals[.paneSplit(paneId: p1, side: .left)] != nil)
        #expect(visuals[.paneSplit(paneId: p3, side: .right)] != nil)
        #expect(visuals[.paneSlot(row: .main, index: 0)] != nil)
        #expect(visuals[.paneSlot(row: .main, index: 2)] != nil)
    }

    // MARK: - R17: cross-tab drag (source not in this row) accepts every target

    @Test
    func r17_crossTabDrag_resolveReturnsValidTargetForCursorOverPane() throws {
        // Source pane lives in a different tab so its frame is absent
        // here. Cross-tab drag is a SUPPORTED operation — no R1+R2
        // adjacency to enforce, every geometric target stays valid.
        // Cross-CONTAINER rejection (main↔drawer) is enforced upstream
        // by the dispatcher, never here.
        let p1 = UUID()
        let p2 = UUID()
        let foreignSource = UUID()
        let frames: [UUID: CGRect] = [
            p1: CGRect(x: 0, y: 0, width: 100, height: 100),
            p2: CGRect(x: 100, y: 0, width: 100, height: 100),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        let cursor = CGPoint(x: 40, y: 50)  // P₁ center, left of midX

        let target = try #require(
            PaneDragCoordinator.resolveTarget(
                location: cursor,
                paneFrames: frames,
                containerBounds: bounds,
                minimizedPaneIds: [],
                sourcePaneId: foreignSource
            )
        )

        #expect(target.sizingTarget == .paneSplit(paneId: p1, side: .left))
    }

    @Test
    func r17_crossTabDrag_targetVisualsIncludesEveryTarget() {
        let p1 = UUID()
        let p2 = UUID()
        let foreignSource = UUID()
        let frames: [UUID: CGRect] = [
            p1: CGRect(x: 0, y: 0, width: 100, height: 100),
            p2: CGRect(x: 100, y: 0, width: 100, height: 100),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)

        let visuals = PaneDragCoordinator.targetVisuals(
            paneFrames: frames,
            containerBounds: bounds,
            minimizedPaneIds: [],
            sourcePaneId: foreignSource
        )

        #expect(visuals[.paneSplit(paneId: p1, side: .left)] != nil)
        #expect(visuals[.paneSplit(paneId: p1, side: .right)] != nil)
        #expect(visuals[.paneSplit(paneId: p2, side: .left)] != nil)
        #expect(visuals[.paneSplit(paneId: p2, side: .right)] != nil)
        #expect(visuals[.paneSlot(row: .main, index: 0)] != nil)
        #expect(visuals[.paneSlot(row: .main, index: 1)] != nil)
        #expect(visuals[.paneSlot(row: .main, index: 2)] != nil)
    }

    // MARK: - Test helpers

    private struct ThreePaneRow {
        let p1: UUID
        let p2: UUID
        let p3: UUID
        let frames: [UUID: CGRect]
        let bounds: CGRect

        static func make() -> Self {
            let p1 = UUID()
            let p2 = UUID()
            let p3 = UUID()
            return Self(
                p1: p1,
                p2: p2,
                p3: p3,
                frames: [
                    p1: CGRect(x: 0, y: 0, width: 100, height: 100),
                    p2: CGRect(x: 100, y: 0, width: 100, height: 100),
                    p3: CGRect(x: 200, y: 0, width: 100, height: 100),
                ],
                bounds: CGRect(x: 0, y: 0, width: 300, height: 100)
            )
        }
    }
}
