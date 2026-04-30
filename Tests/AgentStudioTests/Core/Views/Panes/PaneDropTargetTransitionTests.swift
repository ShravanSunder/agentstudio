import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

/// Issue A — `PaneDropTarget` equality must distinguish targets with
/// the same `paneId + zone` but different `sizingTarget`.
///
/// SwiftUI bindings dedup on equality. `PaneDropTarget` is what flows
/// through the drag overlay's binding. If equality collapses across
/// `sizingTarget`, transitioning the cursor between zones that share
/// `paneId + zone` (e.g. slot 1 between P_a and P_b → split right of
/// P_a) skips the binding update — the visual freezes on the previous
/// zone's render. The user sees a stuck visual that doesn't update
/// when they cross from a slot zone into a center split zone.
@Suite(.serialized)
struct PaneDropTargetTransitionTests {

    @Test
    func slotAndSplit_sharingPaneIdAndZone_areNotEqual() {
        // slot 1 between P_a and P_b → PaneDropTarget(P_a, .right, .paneSlot)
        // split right of P_a            → PaneDropTarget(P_a, .right, .paneSplit)
        // Both share paneId + zone but represent different commit
        // intents and DIFFERENT visuals (slot = boundary marker, split
        // = half-region fill). Equality must distinguish them so the
        // overlay binding fires on transition.
        let paneA = UUID()
        let slotTarget = PaneDropTarget(
            paneId: paneA,
            zone: .right,
            sizingTarget: .paneSlot(row: .main, index: 1)
        )
        let splitTarget = PaneDropTarget(
            paneId: paneA,
            zone: .right,
            sizingTarget: .paneSplit(paneId: paneA, side: .right)
        )

        #expect(slotTarget != splitTarget)
        #expect(slotTarget.hashValue != splitTarget.hashValue)
    }

    @Test
    func sameSizingTarget_sharingPaneIdAndZone_remainEqual() {
        // Sanity: identical targets are still equal — only the
        // sizing-discriminated case is what was broken.
        let paneA = UUID()
        let lhs = PaneDropTarget(
            paneId: paneA,
            zone: .right,
            sizingTarget: .paneSplit(paneId: paneA, side: .right)
        )
        let rhs = PaneDropTarget(
            paneId: paneA,
            zone: .right,
            sizingTarget: .paneSplit(paneId: paneA, side: .right)
        )

        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
    }

    @Test
    func resolveTransition_slotZoneToSplitZone_producesDistinctTargets() throws {
        // End-to-end transition through the coordinator: cursor moves
        // from right 1/4 of P_a (resolves to slot 1) to right half of
        // P_a center (resolves to split P_a right). Both produce
        // PaneDropTargets with paneId=P_a, zone=.right but different
        // sizingTarget. The two MUST be != or the binding skips its
        // update and the visual freezes.
        let paneA = UUID()
        let paneB = UUID()
        let frames: [UUID: CGRect] = [
            paneA: CGRect(x: 0, y: 0, width: 200, height: 100),
            paneB: CGRect(x: 200, y: 0, width: 200, height: 100),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 100)
        let cursorInSlotZone = CGPoint(x: 195, y: 50)  // P_a right 1/4
        let cursorInSplitZone = CGPoint(x: 130, y: 50)  // P_a center right of midX (100)

        let slotTarget = try #require(
            PaneDragCoordinator.resolveTarget(
                location: cursorInSlotZone,
                paneFrames: frames,
                containerBounds: bounds,
                minimizedPaneIds: []
            )
        )
        let splitTarget = try #require(
            PaneDragCoordinator.resolveTarget(
                location: cursorInSplitZone,
                paneFrames: frames,
                containerBounds: bounds,
                minimizedPaneIds: []
            )
        )

        // Both share paneId + zone:
        #expect(slotTarget.paneId == splitTarget.paneId)
        #expect(slotTarget.zone == splitTarget.zone)
        // But sizingTarget differs, so equality must say not equal:
        #expect(slotTarget != splitTarget)
        // And they must produce different visuals (the user-visible signal):
        let slotVisual = PaneDragCoordinator.visual(
            for: slotTarget,
            paneFrames: frames,
            containerBounds: bounds,
            minimizedPaneIds: []
        )
        let splitVisual = PaneDragCoordinator.visual(
            for: splitTarget,
            paneFrames: frames,
            containerBounds: bounds,
            minimizedPaneIds: []
        )
        #expect(slotVisual != splitVisual)
    }
}
