import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class PaneDropTargetResolutionTests {

    @Test
    func test_mixedPaneSet_leftTargetResolution_isIdenticalAcrossKinds() {
        // Arrange. bridgePane is at x=640..940. Center zone is
        // [715, 865). Cursor at x=760 is in the center, left of midX
        // → split-left. (Was x=660 under the old whole-pane-split
        // model; that lands in the left 1/4 zone now, which produces
        // a between-slot target instead.)
        let terminalPaneId = UUID()
        let webviewPaneId = UUID()
        let bridgePaneId = UUID()
        let paneFrames: [UUID: CGRect] = [
            terminalPaneId: CGRect(x: 0, y: 0, width: 300, height: 280),
            webviewPaneId: CGRect(x: 320, y: 0, width: 300, height: 280),
            bridgePaneId: CGRect(x: 640, y: 0, width: 300, height: 280),
        ]
        let location = CGPoint(x: 760, y: 100)

        // Act
        let target = PaneDragCoordinator.resolveTarget(
            location: location, paneFrames: paneFrames, containerBounds: nil, minimizedPaneIds: [])

        // Assert
        #expect(
            target
                == PaneDropTarget(
                    paneId: bridgePaneId, zone: .left, sizingTarget: .paneSplit(paneId: bridgePaneId, side: .left)))
    }

    @Test
    func test_mixedPaneSet_rightTargetResolution_isIdenticalAcrossKinds() {
        // Arrange. webviewPane is at x=320..620. Center zone is
        // [395, 545). Cursor at x=500 is in the center, right of
        // midX (470) → split-right. (Was x=610 under the old whole-
        // pane-split model; that lands in the right 1/4 zone now.)
        let terminalPaneId = UUID()
        let webviewPaneId = UUID()
        let bridgePaneId = UUID()
        let paneFrames: [UUID: CGRect] = [
            terminalPaneId: CGRect(x: 0, y: 0, width: 300, height: 280),
            webviewPaneId: CGRect(x: 320, y: 0, width: 300, height: 280),
            bridgePaneId: CGRect(x: 640, y: 0, width: 300, height: 280),
        ]
        let location = CGPoint(x: 500, y: 100)

        // Act
        let target = PaneDragCoordinator.resolveTarget(
            location: location, paneFrames: paneFrames, containerBounds: nil, minimizedPaneIds: [])

        // Assert
        #expect(
            target
                == PaneDropTarget(
                    paneId: webviewPaneId, zone: .right, sizingTarget: .paneSplit(paneId: webviewPaneId, side: .right)))
    }

    @Test
    func test_mixedPaneSet_edgeCorridor_usesOuterPaneRegardlessOfKind() {
        // Arrange
        let terminalPaneId = UUID()
        let webviewPaneId = UUID()
        let bridgePaneId = UUID()
        let paneFrames: [UUID: CGRect] = [
            terminalPaneId: CGRect(x: 0, y: 0, width: 300, height: 280),
            webviewPaneId: CGRect(x: 320, y: 0, width: 300, height: 280),
            bridgePaneId: CGRect(x: 640, y: 0, width: 300, height: 280),
        ]
        let leftCorridorPoint = CGPoint(x: -8, y: 120)
        let rightCorridorPoint = CGPoint(x: 944, y: 120)

        // Act
        let leftTarget = PaneDragCoordinator.resolveTarget(
            location: leftCorridorPoint,
            paneFrames: paneFrames,
            containerBounds: nil,
            minimizedPaneIds: []
        )
        let rightTarget = PaneDragCoordinator.resolveTarget(
            location: rightCorridorPoint,
            paneFrames: paneFrames,
            containerBounds: nil,
            minimizedPaneIds: []
        )

        // Assert — corridor drops produce slot targets at the row edges,
        // regardless of the inner pane's kind (mixed terminal + bridge).
        #expect(
            leftTarget
                == PaneDropTarget(
                    paneId: terminalPaneId, zone: .left, sizingTarget: .paneSlot(row: .main, index: 0)))
        #expect(
            rightTarget
                == PaneDropTarget(
                    paneId: bridgePaneId, zone: .right, sizingTarget: .paneSlot(row: .main, index: 3)))
    }
}
