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
    func paneDragCoordinator_visualForLeftSplit_isHalfRegionOnLeft() {
        let paneA = UUID()
        let paneFrames: [UUID: CGRect] = [paneA: Self.paneAFrame]

        let target = PaneDropTarget(
            paneId: paneA,
            zone: .left,
            sizingTarget: .paneSplit(paneId: paneA, side: .left)
        )

        let visual = PaneDragCoordinator.visual(
            for: target,
            paneFrames: paneFrames,
            containerBounds: Self.paneAFrame,
            minimizedPaneIds: []
        )

        #expect(visual == .region(CGRect(x: 0, y: 0, width: 100, height: 100)))
    }

    @Test
    func paneDragCoordinator_visualForRightSplit_isHalfRegionOnRight() {
        let paneA = UUID()
        let paneFrames: [UUID: CGRect] = [paneA: Self.paneAFrame]

        let target = PaneDropTarget(
            paneId: paneA,
            zone: .right,
            sizingTarget: .paneSplit(paneId: paneA, side: .right)
        )

        let visual = PaneDragCoordinator.visual(
            for: target,
            paneFrames: paneFrames,
            containerBounds: Self.paneAFrame,
            minimizedPaneIds: []
        )

        #expect(visual == .region(CGRect(x: 100, y: 0, width: 100, height: 100)))
    }

    @Test
    func paneDragCoordinator_visualForSlotInsert_isInsertionMarker() {
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

        let visual = PaneDragCoordinator.visual(
            for: betweenTarget,
            paneFrames: paneFrames,
            containerBounds: containerBounds,
            minimizedPaneIds: []
        )

        guard case .insertionMarker(let markerRect) = visual else {
            Issue.record("expected insertion marker, got \(String(describing: visual))")
            return
        }
        // Marker should be a thin vertical bar centered on the boundary at x=200.
        #expect(markerRect.midX == 200)
        #expect(markerRect.height == 100)
    }
}
