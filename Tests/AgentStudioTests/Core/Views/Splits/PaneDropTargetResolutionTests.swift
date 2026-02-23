import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class PaneDropTargetResolutionTests {

    @Test
    func test_mixedPaneSet_leftTargetResolution_isIdenticalAcrossKinds() {
        // Arrange
        let terminalPaneId = UUID()
        let webviewPaneId = UUID()
        let bridgePaneId = UUID()
        let paneFrames: [UUID: CGRect] = [
            terminalPaneId: CGRect(x: 0, y: 0, width: 300, height: 280),
            webviewPaneId: CGRect(x: 320, y: 0, width: 300, height: 280),
            bridgePaneId: CGRect(x: 640, y: 0, width: 300, height: 280),
        ]
        let location = CGPoint(x: 660, y: 100)

        // Act
        let target = PaneDragCoordinator.resolveTarget(location: location, paneFrames: paneFrames)

        // Assert
        #expect(target == PaneDropTarget(paneId: bridgePaneId, zone: .left))
    }

    @Test
    func test_mixedPaneSet_rightTargetResolution_isIdenticalAcrossKinds() {
        // Arrange
        let terminalPaneId = UUID()
        let webviewPaneId = UUID()
        let bridgePaneId = UUID()
        let paneFrames: [UUID: CGRect] = [
            terminalPaneId: CGRect(x: 0, y: 0, width: 300, height: 280),
            webviewPaneId: CGRect(x: 320, y: 0, width: 300, height: 280),
            bridgePaneId: CGRect(x: 640, y: 0, width: 300, height: 280),
        ]
        let location = CGPoint(x: 610, y: 100)

        // Act
        let target = PaneDragCoordinator.resolveTarget(location: location, paneFrames: paneFrames)

        // Assert
        #expect(target == PaneDropTarget(paneId: webviewPaneId, zone: .right))
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
            paneFrames: paneFrames
        )
        let rightTarget = PaneDragCoordinator.resolveTarget(
            location: rightCorridorPoint,
            paneFrames: paneFrames
        )

        // Assert
        #expect(leftTarget == PaneDropTarget(paneId: terminalPaneId, zone: .left))
        #expect(rightTarget == PaneDropTarget(paneId: bridgePaneId, zone: .right))
    }
}
