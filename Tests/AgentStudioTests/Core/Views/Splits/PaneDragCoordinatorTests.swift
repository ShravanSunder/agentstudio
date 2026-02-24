import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class PaneDragCoordinatorTests {

    @Test
    func test_resolveTarget_insideLeftHalf_returnsLeftZone() {
        // Arrange
        let paneId = UUID()
        let paneFrames = [paneId: CGRect(x: 100, y: 200, width: 400, height: 300)]
        let location = CGPoint(x: 150, y: 300)

        // Act
        let result = PaneDragCoordinator.resolveTarget(location: location, paneFrames: paneFrames)

        // Assert
        #expect(result == PaneDropTarget(paneId: paneId, zone: .left))
    }

    @Test
    func test_resolveTarget_insideRightHalf_returnsRightZone() {
        // Arrange
        let paneId = UUID()
        let paneFrames = [paneId: CGRect(x: 100, y: 200, width: 400, height: 300)]
        let location = CGPoint(x: 450, y: 300)

        // Act
        let result = PaneDragCoordinator.resolveTarget(location: location, paneFrames: paneFrames)

        // Assert
        #expect(result == PaneDropTarget(paneId: paneId, zone: .right))
    }

    @Test
    func test_resolveTarget_usesLocalPointWhenCalculatingZone() {
        // Arrange
        // location.x = 525 appears "right" in absolute terms, but local x = 25 of width 200.
        let paneId = UUID()
        let paneFrames = [paneId: CGRect(x: 500, y: 200, width: 200, height: 200)]
        let location = CGPoint(x: 525, y: 250)

        // Act
        let result = PaneDragCoordinator.resolveTarget(location: location, paneFrames: paneFrames)

        // Assert
        #expect(result == PaneDropTarget(paneId: paneId, zone: .left))
    }

    @Test
    func test_resolveTarget_outsideAllPaneFrames_returnsNil() {
        // Arrange
        let paneId = UUID()
        let paneFrames = [paneId: CGRect(x: 100, y: 200, width: 400, height: 300)]
        let location = CGPoint(x: 10, y: 10)

        // Act
        let result = PaneDragCoordinator.resolveTarget(location: location, paneFrames: paneFrames)

        // Assert
        #expect(result == nil)
    }

    @Test
    func test_target_leftOfLeftmostPane_returnsLeftZoneOfLeftmostPane() {
        // Arrange
        let leftmostPaneId = UUID()
        let middlePaneId = UUID()
        let paneFrames: [UUID: CGRect] = [
            leftmostPaneId: CGRect(x: 100, y: 200, width: 200, height: 200),
            middlePaneId: CGRect(x: 320, y: 200, width: 200, height: 200),
        ]
        let location = CGPoint(x: 99, y: 250)

        // Act
        let result = PaneDragCoordinator.resolveTarget(location: location, paneFrames: paneFrames)

        // Assert
        #expect(result == PaneDropTarget(paneId: leftmostPaneId, zone: .left))
    }

    @Test
    func test_target_rightOfRightmostPane_returnsRightZoneOfRightmostPane() {
        // Arrange
        let leftPaneId = UUID()
        let rightmostPaneId = UUID()
        let paneFrames: [UUID: CGRect] = [
            leftPaneId: CGRect(x: 100, y: 200, width: 200, height: 200),
            rightmostPaneId: CGRect(x: 320, y: 200, width: 200, height: 200),
        ]
        let location = CGPoint(x: 521, y: 250)

        // Act
        let result = PaneDragCoordinator.resolveTarget(location: location, paneFrames: paneFrames)

        // Assert
        #expect(result == PaneDropTarget(paneId: rightmostPaneId, zone: .right))
    }

    @Test
    func test_target_insideLeftContainerGap_resolvesToLeftmostPaneWhenContainerBoundsProvided() {
        // Arrange
        let leftmostPaneId = UUID()
        let rightPaneId = UUID()
        let paneFrames: [UUID: CGRect] = [
            leftmostPaneId: CGRect(x: 8, y: 80, width: 240, height: 300),
            rightPaneId: CGRect(x: 264, y: 80, width: 240, height: 300),
        ]
        let containerBounds = CGRect(x: 0, y: 0, width: 520, height: 400)
        let location = CGPoint(x: 4, y: 200)

        // Act
        let result = PaneDragCoordinator.resolveTarget(
            location: location,
            paneFrames: paneFrames,
            containerBounds: containerBounds
        )

        // Assert
        #expect(result == PaneDropTarget(paneId: leftmostPaneId, zone: .left))
    }

    @Test
    func test_target_insideRightContainerGap_resolvesToRightmostPaneWhenContainerBoundsProvided() {
        // Arrange
        let leftPaneId = UUID()
        let rightmostPaneId = UUID()
        let paneFrames: [UUID: CGRect] = [
            leftPaneId: CGRect(x: 16, y: 40, width: 220, height: 280),
            rightmostPaneId: CGRect(x: 252, y: 40, width: 260, height: 280),
        ]
        let containerBounds = CGRect(x: 0, y: 0, width: 520, height: 360)
        let location = CGPoint(x: 516, y: 180)

        // Act
        let result = PaneDragCoordinator.resolveTarget(
            location: location,
            paneFrames: paneFrames,
            containerBounds: containerBounds
        )

        // Assert
        #expect(result == PaneDropTarget(paneId: rightmostPaneId, zone: .right))
    }

    @Test
    func test_resolveTarget_overlappingFrames_prefersSmallerAreaFrame() {
        // Arrange
        let largerPaneId = UUID()
        let smallerPaneId = UUID()
        let paneFrames: [UUID: CGRect] = [
            largerPaneId: CGRect(x: 100, y: 100, width: 300, height: 260),
            smallerPaneId: CGRect(x: 180, y: 130, width: 160, height: 180),
        ]
        let location = CGPoint(x: 220, y: 220)

        // Act
        let result = PaneDragCoordinator.resolveTarget(location: location, paneFrames: paneFrames)

        // Assert
        #expect(result?.paneId == smallerPaneId)
    }

    @Test
    func test_target_leftCorridor_usesCombinedVerticalBounds() {
        // Arrange
        let leftmostPaneId = UUID()
        let rightPaneId = UUID()
        let paneFrames: [UUID: CGRect] = [
            leftmostPaneId: CGRect(x: 100, y: 220, width: 200, height: 120),
            rightPaneId: CGRect(x: 320, y: 80, width: 200, height: 340),
        ]
        let location = CGPoint(x: 90, y: 380)

        // Act
        let result = PaneDragCoordinator.resolveTarget(location: location, paneFrames: paneFrames)

        // Assert
        #expect(result == PaneDropTarget(paneId: leftmostPaneId, zone: .left))
    }

    @Test
    func test_resolveLatchedTarget_keepsCurrentTarget_whenLocationTemporarilyInvalid() {
        // Arrange
        let paneId = UUID()
        let currentTarget = PaneDropTarget(paneId: paneId, zone: .left)
        let paneFrames: [UUID: CGRect] = [
            paneId: CGRect(x: 100, y: 100, width: 200, height: 200)
        ]
        let gapLocation = CGPoint(x: 350, y: 150)

        // Act
        let result = PaneDragCoordinator.resolveLatchedTarget(
            location: gapLocation,
            paneFrames: paneFrames,
            currentTarget: currentTarget,
            shouldAcceptDrop: { _, _ in true }
        )

        // Assert
        #expect(result == currentTarget)
    }

    @Test
    func test_resolveLatchedTarget_switchesToNewTarget_whenValidTargetAppears() {
        // Arrange
        let firstPaneId = UUID()
        let secondPaneId = UUID()
        let currentTarget = PaneDropTarget(paneId: firstPaneId, zone: .left)
        let paneFrames: [UUID: CGRect] = [
            firstPaneId: CGRect(x: 100, y: 100, width: 200, height: 200),
            secondPaneId: CGRect(x: 320, y: 100, width: 200, height: 200),
        ]
        let newLocation = CGPoint(x: 470, y: 150)

        // Act
        let result = PaneDragCoordinator.resolveLatchedTarget(
            location: newLocation,
            paneFrames: paneFrames,
            currentTarget: currentTarget,
            shouldAcceptDrop: { _, _ in true }
        )

        // Assert
        #expect(result == PaneDropTarget(paneId: secondPaneId, zone: .right))
    }

    @Test
    func test_resolveLatchedTarget_clearsWhenCurrentTargetRejected() {
        // Arrange
        let paneId = UUID()
        let currentTarget = PaneDropTarget(paneId: paneId, zone: .left)
        let paneFrames: [UUID: CGRect] = [
            paneId: CGRect(x: 100, y: 100, width: 200, height: 200)
        ]
        let gapLocation = CGPoint(x: 10, y: 10)

        // Act
        let result = PaneDragCoordinator.resolveLatchedTarget(
            location: gapLocation,
            paneFrames: paneFrames,
            currentTarget: currentTarget,
            shouldAcceptDrop: { _, _ in false }
        )

        // Assert
        #expect(result == nil)
    }
}
