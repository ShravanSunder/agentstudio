import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

/// Pin the shared visual model main + drawer use to render drag
/// targets:
///
///   ▸ `.region(rect)` — soft fill, no border line. Used for splits.
///   ▸ `.insertionMarker(rect)` — bright bar. Used for slot inserts
///     (between panes, at row edges, or new-row creation bands).
///
/// Per Option B the split visual fills only the cursor's HALF of
/// the pane (so the user sees which side the new pane will land).
@Suite(.serialized)
struct DropTargetVisualTests {
    private static let paneAFrame = CGRect(x: 0, y: 0, width: 200, height: 100)

    @Test
    func paneDragCoordinator_visualForLeftSplit_isHalfRegionWithoutMarker() throws {
        let paneA = UUID()
        let paneFrames: [UUID: CGRect] = [paneA: Self.paneAFrame]

        let target = PaneDropTarget(
            paneId: paneA,
            zone: .left,
            sizingTarget: .paneSplit(paneId: paneA, side: .left)
        )

        let visual = try #require(
            PaneDragCoordinator.visual(
                for: target,
                paneFrames: paneFrames,
                containerBounds: Self.paneAFrame,
                minimizedPaneIds: []
            )
        )

        #expect(visual.region == CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(visual.insertionMarker == nil)
    }

    @Test
    func paneDragCoordinator_visualForRightSplit_isHalfRegionOnRightWithoutMarker() throws {
        let paneA = UUID()
        let paneFrames: [UUID: CGRect] = [paneA: Self.paneAFrame]

        let target = PaneDropTarget(
            paneId: paneA,
            zone: .right,
            sizingTarget: .paneSplit(paneId: paneA, side: .right)
        )

        let visual = try #require(
            PaneDragCoordinator.visual(
                for: target,
                paneFrames: paneFrames,
                containerBounds: Self.paneAFrame,
                minimizedPaneIds: []
            )
        )

        #expect(visual.region == CGRect(x: 100, y: 0, width: 100, height: 100))
        #expect(visual.insertionMarker == nil)
    }

    /// Issue C — when the two flanking panes have different widths,
    /// the in-between visual must be SYMMETRIC around the boundary so
    /// the highlight stays the same width as the cursor moves between
    /// boundaries. Asymmetric per-pane 1/4 widths cause the highlight
    /// to visibly resize and shift across the boundary; the symmetric
    /// clamp gives a snap-to-boundary feel.
    @Test
    func paneDragCoordinator_visualForSlotInsert_betweenAsymmetricPanes_isSymmetricAroundBoundary() throws {
        let paneA = UUID()  // wide
        let paneB = UUID()  // narrow
        let paneFrames: [UUID: CGRect] = [
            paneA: CGRect(x: 0, y: 0, width: 400, height: 100),  // 1/4 = 100
            paneB: CGRect(x: 400, y: 0, width: 100, height: 100),  // 1/4 = 25
        ]
        let containerBounds = CGRect(x: 0, y: 0, width: 500, height: 100)

        let betweenTarget = PaneDropTarget(
            paneId: paneA,
            zone: .right,
            sizingTarget: .paneSlot(row: .main, index: 1)
        )

        let visual = try #require(
            PaneDragCoordinator.visual(
                for: betweenTarget,
                paneFrames: paneFrames,
                containerBounds: containerBounds,
                minimizedPaneIds: []
            )
        )
        let markerRect = try #require(visual.insertionMarker)

        // Symmetric clamp: half = max(min(100, 25), 24pt floor) = 25,
        // so region width = 50, centered on boundary x=400.
        #expect(visual.region == CGRect(x: 375, y: 0, width: 50, height: 100))
        #expect(markerRect.midX == 400)
    }

    /// Codex P1 — when panes are narrow enough that the natural side
    /// zone collapses to half-pane width (sideZoneFloor * 2 >= width),
    /// the painted slot region MUST also collapse to per-side half-
    /// pane width. Otherwise the visual paints into adjacent slot zones
    /// and clicking inside the painted area resolves to the wrong slot.
    ///
    /// Two 40pt panes touching at boundary x=40:
    ///   sideWidth(for: 40pt frame, floor: 24) = min(max(10, 24), 20) = 20
    ///   So slot 1 hover hit = [20..60] (right half of left + left half of right).
    ///   Visual must match: half-width 20 around boundary = region [20..60].
    @Test
    func paneDragCoordinator_visualForSlotInsert_betweenNarrowPanes_capsAtHalfPaneWidth() throws {
        let paneA = UUID()
        let paneB = UUID()
        let paneFrames: [UUID: CGRect] = [
            paneA: CGRect(x: 0, y: 0, width: 40, height: 100),
            paneB: CGRect(x: 40, y: 0, width: 40, height: 100),
        ]
        let containerBounds = CGRect(x: 0, y: 0, width: 80, height: 100)

        let betweenTarget = PaneDropTarget(
            paneId: paneA,
            zone: .right,
            sizingTarget: .paneSlot(row: .main, index: 1)
        )

        let visual = try #require(
            PaneDragCoordinator.visual(
                for: betweenTarget,
                paneFrames: paneFrames,
                containerBounds: containerBounds,
                minimizedPaneIds: []
            )
        )

        // Region width = 2 * 20 = 40 centered on boundary x=40 → [20..60].
        // Hit zone for slot 1 also = [20..60], so visual matches commit area.
        #expect(visual.region == CGRect(x: 20, y: 0, width: 40, height: 100))
    }

    /// Issue C — narrow panes hit the side-zone floor (24pt). When
    /// both panes have natural 1/4 widths below the floor, both sides
    /// should grow to the floor for a 48pt-wide centered region — but
    /// only when the floor doesn't exceed each pane's half-width cap.
    @Test
    func paneDragCoordinator_visualForSlotInsert_betweenVeryNarrowPanes_floorsToSideZoneFloor() throws {
        let paneA = UUID()
        let paneB = UUID()
        let paneFrames: [UUID: CGRect] = [
            paneA: CGRect(x: 0, y: 0, width: 60, height: 100),  // 1/4 = 15 < 24pt floor
            paneB: CGRect(x: 60, y: 0, width: 60, height: 100),  // 1/4 = 15 < 24pt floor
        ]
        let containerBounds = CGRect(x: 0, y: 0, width: 120, height: 100)

        let betweenTarget = PaneDropTarget(
            paneId: paneA,
            zone: .right,
            sizingTarget: .paneSlot(row: .main, index: 1)
        )

        let visual = try #require(
            PaneDragCoordinator.visual(
                for: betweenTarget,
                paneFrames: paneFrames,
                containerBounds: containerBounds,
                minimizedPaneIds: []
            )
        )

        // Both 1/4 = 15 → clamped to floor 24 → region = 48pt centered on x=60.
        #expect(visual.region == CGRect(x: 36, y: 0, width: 48, height: 100))
    }

    /// Codex test gap — slot visual with a degenerate (0pt) neighbor.
    /// The P1 fix caps half-width at the smaller neighbor's side width;
    /// for a 0pt pane sideWidth = min(max(0, 24), 0) = 0. The other
    /// side stays at its computed sideWidth. The visual collapses to
    /// just one side's contribution. No crash, no overflow.
    @Test
    func paneDragCoordinator_visualForSlotInsert_zeroWidthNeighbor_collapsesToOtherSide() throws {
        let paneA = UUID()  // normal width
        let paneZero = UUID()  // degenerate 0pt
        let paneFrames: [UUID: CGRect] = [
            paneA: CGRect(x: 0, y: 0, width: 200, height: 100),  // sideWidth = max(50,24)=50, capped at 100 → 50
            paneZero: CGRect(x: 200, y: 0, width: 0, height: 100),  // sideWidth = min(max(0,24), 0) = 0
        ]
        let containerBounds = CGRect(x: 0, y: 0, width: 200, height: 100)

        let betweenTarget = PaneDropTarget(
            paneId: paneA,
            zone: .right,
            sizingTarget: .paneSlot(row: .main, index: 1)
        )

        let visual = try #require(
            PaneDragCoordinator.visual(
                for: betweenTarget,
                paneFrames: paneFrames,
                containerBounds: containerBounds,
                minimizedPaneIds: []
            )
        )

        // halfWidth = min(50, 0) = 0 → region width = 0, centered on
        // boundary x=200. No overpaint into either pane's hit zone.
        #expect(visual.region.width == 0)
        #expect(visual.region.midX == 200)
    }

    @Test
    func paneDragCoordinator_visualForSlotInsert_hasZoneRegionAndMarker() throws {
        let paneA = UUID()
        let paneB = UUID()
        let paneFrames: [UUID: CGRect] = [
            paneA: CGRect(x: 0, y: 0, width: 200, height: 100),
            paneB: CGRect(x: 200, y: 0, width: 200, height: 100),
        ]
        let containerBounds = CGRect(x: 0, y: 0, width: 400, height: 100)

        // Slot index 1 = between paneA and paneB.
        let betweenTarget = PaneDropTarget(
            paneId: paneA,
            zone: .right,
            sizingTarget: .paneSlot(row: .main, index: 1)
        )

        let visual = try #require(
            PaneDragCoordinator.visual(
                for: betweenTarget,
                paneFrames: paneFrames,
                containerBounds: containerBounds,
                minimizedPaneIds: []
            )
        )
        let markerRect = try #require(visual.insertionMarker)

        // Region: right 1/4 of paneA (x=150..200) + left 1/4 of paneB
        // (x=200..250) = combined zone x=150..250.
        #expect(visual.region == CGRect(x: 150, y: 0, width: 100, height: 100))
        // Marker: thin vertical bar centered on the boundary at x=200.
        #expect(markerRect.midX == 200)
        #expect(markerRect.height == 100)
    }
}
