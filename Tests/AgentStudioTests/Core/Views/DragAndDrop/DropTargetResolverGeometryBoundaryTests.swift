import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

/// R18 — DropTargetResolver is pure geometry. It is source-blind by
/// construction: source-pane filtering is a higher layer's concern
/// (the coordinators wrapping the resolver). These tests pin that
/// architectural boundary so a future "fix" can't muddy the resolver
/// with source semantics. If you need to filter self/adjacent targets,
/// do it in the source-aware adapter layer (PaneDragCoordinator,
/// DrawerPaneDragCoordinator), never in the raw resolver.
@Suite(.serialized)
struct DropTargetResolverGeometryBoundaryTests {
    @Test
    func resolver_resolvesSplitCandidateForCenterCursor_evenWhenPaneCouldBeSource() {
        // Arrange — three-pane row, cursor in P₂'s left half.
        // The resolver has NO source-pane parameter, so it must return
        // the geometric candidate regardless of which pane is "source"
        // at the higher layer.
        let p1 = UUID()
        let p2 = UUID()
        let p3 = UUID()
        let frames: [UUID: CGRect] = [
            p1: CGRect(x: 0, y: 0, width: 100, height: 100),
            p2: CGRect(x: 100, y: 0, width: 100, height: 100),
            p3: CGRect(x: 200, y: 0, width: 100, height: 100),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 100)
        // P₂ center zone is [125, 175); cursor at 130 is inside, left of midX (150).
        let cursor = CGPoint(x: 130, y: 50)

        // Act
        let target = DropTargetResolver.resolve(
            location: cursor,
            rows: [.main: [p1, p2, p3]],
            paneFrames: frames,
            containerBounds: bounds,
            config: .main,
            splittablePanes: [p1, p2, p3]
        )

        // Assert — raw resolver returns split(P₂, .left). Source-blind.
        #expect(target == .paneSplit(paneId: p2, side: .left))
    }

    @Test
    func resolver_targetVisuals_includesEverySplittablePaneRegardlessOfSource() {
        // Arrange
        let p1 = UUID()
        let p2 = UUID()
        let p3 = UUID()
        let frames: [UUID: CGRect] = [
            p1: CGRect(x: 0, y: 0, width: 100, height: 100),
            p2: CGRect(x: 100, y: 0, width: 100, height: 100),
            p3: CGRect(x: 200, y: 0, width: 100, height: 100),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 100)

        // Act — resolver builds visuals for every pane in splittablePanes.
        let visuals = DropTargetResolver.targetVisuals(
            rows: [.main: [p1, p2, p3]],
            paneFrames: frames,
            containerBounds: bounds,
            config: .main,
            splittablePanes: [p1, p2, p3]
        )

        // Assert — all 6 split visuals + 4 slot visuals are present.
        // Source filtering does not happen here.
        #expect(visuals[.paneSplit(paneId: p1, side: .left)] != nil)
        #expect(visuals[.paneSplit(paneId: p1, side: .right)] != nil)
        #expect(visuals[.paneSplit(paneId: p2, side: .left)] != nil)
        #expect(visuals[.paneSplit(paneId: p2, side: .right)] != nil)
        #expect(visuals[.paneSplit(paneId: p3, side: .left)] != nil)
        #expect(visuals[.paneSplit(paneId: p3, side: .right)] != nil)
        #expect(visuals[.paneSlot(row: .main, index: 0)] != nil)
        #expect(visuals[.paneSlot(row: .main, index: 1)] != nil)
        #expect(visuals[.paneSlot(row: .main, index: 2)] != nil)
        #expect(visuals[.paneSlot(row: .main, index: 3)] != nil)
    }

    @Test
    func resolver_resolvesSlotCandidate_inSideZoneRegardlessOfSource() {
        // Arrange — cursor in right 1/4 of P₁ → resolver returns slot 1
        // (the inter-pane boundary). Even if S = P₂ at the higher layer,
        // the raw resolver does not know.
        let p1 = UUID()
        let p2 = UUID()
        let frames: [UUID: CGRect] = [
            p1: CGRect(x: 0, y: 0, width: 100, height: 100),
            p2: CGRect(x: 100, y: 0, width: 100, height: 100),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        let cursor = CGPoint(x: 90, y: 50)  // P₁ right 1/4 zone

        // Act
        let target = DropTargetResolver.resolve(
            location: cursor,
            rows: [.main: [p1, p2]],
            paneFrames: frames,
            containerBounds: bounds,
            config: .main,
            splittablePanes: [p1, p2]
        )

        // Assert
        #expect(target == .paneSlot(row: .main, index: 1))
    }
}
