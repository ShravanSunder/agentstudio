import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

/// R5 — `PaneDragCoordinator.resolveLatchedTarget` source-filter rules.
///
///   ▸ When the cursor moves OVER a self/adjacent zone (a zone the
///     source filter rejects at the resolved-candidate level), the
///     latch DROPS to nil. The user is signaling intent to land on a
///     no-op target; we refuse to paint stale state.
///
///   ▸ When the cursor moves into TRANSIENT EMPTY GEOMETRY (no pane
///     under the cursor at all), the latch is RETAINED — this preserves
///     the existing "ride through layout jitter" behavior so a brief
///     gap between panes does not flicker the overlay.
///
/// These two cases are distinct on purpose. Without the distinction,
/// implementations drift: either the latch becomes too sticky (paints
/// over invalid zones) or too jumpy (flickers through gaps).
@Suite(.serialized)
struct PaneDragLatchedSourceFilterTests {

    @Test
    func r5_latched_dropsLatchWhenCursorMovesOverSourceCenter() {
        // Arrange — three panes; latched on a foreign split target;
        // cursor moves to S's center (a rejected zone).
        let setup = ThreePaneRow.make()
        let validForeignTarget = PaneDropTarget(
            paneId: setup.p3,
            zone: .left,
            sizingTarget: .paneSplit(paneId: setup.p3, side: .left)
        )
        let cursorOnSourceCenter = CGPoint(x: setup.frames[setup.p2]!.midX, y: 50)

        // Act
        let result = PaneDragCoordinator.resolveLatchedTarget(
            location: cursorOnSourceCenter,
            paneFrames: setup.frames,
            containerBounds: setup.bounds,
            minimizedPaneIds: [],
            currentTarget: validForeignTarget,
            isShiftHeld: false,
            sourcePaneId: setup.p2,
            shouldAcceptDrop: { _, _, _ in true }
        )

        // Assert
        #expect(result == nil)
    }

    @Test
    func r5_latched_promotesAdjacentSlotOverForeignSiblingToSplit() throws {
        // Arrange — cursor moves into right 1/4 of P₁ (would resolve to
        // slot 1 = adjacent to S=P₂). Sibling-promotion exception
        // applies: result is split(P₁, .right), not nil.
        let setup = ThreePaneRow.make()
        let validForeignTarget = PaneDropTarget(
            paneId: setup.p3,
            zone: .left,
            sizingTarget: .paneSplit(paneId: setup.p3, side: .left)
        )
        let p1Frame = setup.frames[setup.p1]!
        let cursorInAdjacentZone = CGPoint(x: p1Frame.maxX - 5, y: 50)

        // Act
        let result = try #require(
            PaneDragCoordinator.resolveLatchedTarget(
                location: cursorInAdjacentZone,
                paneFrames: setup.frames,
                containerBounds: setup.bounds,
                minimizedPaneIds: [],
                currentTarget: validForeignTarget,
                isShiftHeld: false,
                sourcePaneId: setup.p2,
                shouldAcceptDrop: { _, _, _ in true }
            )
        )

        // Assert
        #expect(result.sizingTarget == .paneSplit(paneId: setup.p1, side: .right))
    }

    @Test
    func r5_latched_dropsLatchWhenCursorOverSourcePaneOwnQuarterZone() {
        // Arrange — cursor in right 1/4 of S. Promotion can't apply
        // because the containing pane IS source. Latch drops.
        let setup = ThreePaneRow.make()
        let validForeignTarget = PaneDropTarget(
            paneId: setup.p3,
            zone: .left,
            sizingTarget: .paneSplit(paneId: setup.p3, side: .left)
        )
        let sourceFrame = setup.frames[setup.p2]!
        let cursorOnSourceRightQuarter = CGPoint(x: sourceFrame.maxX - 5, y: 50)

        // Act
        let result = PaneDragCoordinator.resolveLatchedTarget(
            location: cursorOnSourceRightQuarter,
            paneFrames: setup.frames,
            containerBounds: setup.bounds,
            minimizedPaneIds: [],
            currentTarget: validForeignTarget,
            isShiftHeld: false,
            sourcePaneId: setup.p2,
            shouldAcceptDrop: { _, _, _ in true }
        )

        // Assert
        #expect(result == nil)
    }

    @Test
    func r5_latched_keepsLatchWhenCursorEntersTransientEmptyGeometry() {
        // Arrange — cursor leaves the pane area entirely (way outside
        // containerBounds). No geometric candidate, no source rejection.
        // Latch should be retained ("ride through jitter").
        let setup = ThreePaneRow.make()
        let validForeignTarget = PaneDropTarget(
            paneId: setup.p3,
            zone: .left,
            sizingTarget: .paneSplit(paneId: setup.p3, side: .left)
        )
        let cursorInVoid = CGPoint(x: 5000, y: 5000)

        // Act
        let result = PaneDragCoordinator.resolveLatchedTarget(
            location: cursorInVoid,
            paneFrames: setup.frames,
            containerBounds: setup.bounds,
            minimizedPaneIds: [],
            currentTarget: validForeignTarget,
            isShiftHeld: false,
            sourcePaneId: setup.p2,
            shouldAcceptDrop: { _, _, _ in true }
        )

        // Assert
        #expect(result == validForeignTarget)
    }

    @Test
    func r5_latched_acquiresNewTargetWhenCursorMovesToValidForeignZone() {
        // Arrange — no current target; cursor lands on a valid foreign
        // zone (P₃ split-right).
        let setup = ThreePaneRow.make()
        let p3Frame = setup.frames[setup.p3]!
        let cursorOnP3RightHalf = CGPoint(x: p3Frame.midX + 5, y: 50)

        // Act
        let result = PaneDragCoordinator.resolveLatchedTarget(
            location: cursorOnP3RightHalf,
            paneFrames: setup.frames,
            containerBounds: setup.bounds,
            minimizedPaneIds: [],
            currentTarget: nil,
            isShiftHeld: false,
            sourcePaneId: setup.p2,
            shouldAcceptDrop: { _, _, _ in true }
        )

        // Assert
        #expect(
            result
                == PaneDropTarget(
                    paneId: setup.p3,
                    zone: .right,
                    sizingTarget: .paneSplit(paneId: setup.p3, side: .right)
                ))
    }

    @Test
    func r5_latched_acceptsLatchWhenSourceFromAnotherTab() {
        // Cross-tab drag: source pane is in a different tab so it has
        // no frame in this row. R5 still applies for the geometric
        // candidate; with no source adjacency to enforce, every
        // geometric target is accepted (same as R17 cross-tab path).
        let setup = ThreePaneRow.make()
        let foreignSource = UUID()
        let cursorOnP3LeftHalf = CGPoint(x: setup.frames[setup.p3]!.midX - 5, y: 50)

        let result = PaneDragCoordinator.resolveLatchedTarget(
            location: cursorOnP3LeftHalf,
            paneFrames: setup.frames,
            containerBounds: setup.bounds,
            minimizedPaneIds: [],
            currentTarget: nil,
            isShiftHeld: false,
            sourcePaneId: foreignSource,
            shouldAcceptDrop: { _, _, _ in true }
        )

        #expect(result?.sizingTarget == .paneSplit(paneId: setup.p3, side: .left))
    }

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
