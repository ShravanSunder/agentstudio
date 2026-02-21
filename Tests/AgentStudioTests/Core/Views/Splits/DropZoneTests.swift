 import CoreGraphics
import Testing
import Foundation

@testable import AgentStudio

@Suite(.serialized)
final class DropZoneTests {

    // MARK: - Edge Proximity Detection

    @Test

    func test_calculate_nearLeftEdge_returnsLeft() {
        // Arrange
        let size = CGSize(width: 400, height: 400)
        let point = CGPoint(x: 10, y: 200)

        // Act
        let result = DropZone.calculate(at: point, in: size)

        // Assert
        #expect(result == .left)
    }

    @Test

    func test_calculate_nearRightEdge_returnsRight() {
        // Arrange
        let size = CGSize(width: 400, height: 400)
        let point = CGPoint(x: 390, y: 200)

        // Act
        let result = DropZone.calculate(at: point, in: size)

        // Assert
        #expect(result == .right)
    }

    @Test

    func test_calculate_nearTopEdge_returnsLeftOrRight() {
        // Vertical splits disabled — top/bottom snap to left/right based on x position.
        // Arrange — x=200 is exactly half of 400, so relX=0.5 → right (>= 0.5)
        let size = CGSize(width: 400, height: 400)
        let pointCenter = CGPoint(x: 200, y: 10)
        let pointLeftSide = CGPoint(x: 100, y: 10)

        // Act & Assert
        #expect(DropZone.calculate(at: pointCenter, in: size) == .right)
        #expect(DropZone.calculate(at: pointLeftSide, in: size) == .left)
    }

    @Test

    func test_calculate_nearBottomEdge_returnsLeftOrRight() {
        // Vertical splits disabled — near bottom edge snaps to left/right.
        // Arrange
        let size = CGSize(width: 400, height: 400)
        let pointRight = CGPoint(x: 300, y: 390)
        let pointLeft = CGPoint(x: 100, y: 390)

        // Act & Assert
        #expect(DropZone.calculate(at: pointRight, in: size) == .right)
        #expect(DropZone.calculate(at: pointLeft, in: size) == .left)
    }

    // MARK: - Tie-Breaking

    @Test

    func test_calculate_topLeftCorner_returnsLeft() {
        // At (0, 0): distToLeft=0, distToTop=0. Left wins (checked first in if-chain).
        // Arrange
        let size = CGSize(width: 400, height: 400)
        let point = CGPoint.zero

        // Act
        let result = DropZone.calculate(at: point, in: size)

        // Assert
        #expect(result == .left)
    }

    @Test

    func test_calculate_exactCenter_returnsRight() {
        // relX = 0.5, which is not < 0.5, so returns .right
        // Arrange
        let size = CGSize(width: 400, height: 400)
        let point = CGPoint(x: 200, y: 200)

        // Act
        let result = DropZone.calculate(at: point, in: size)

        // Assert
        #expect(result == .right)
    }

    // MARK: - Degenerate Sizes

    @Test

    func test_calculate_zeroWidth_returnsRight() {
        // Arrange
        let size = CGSize(width: 0, height: 400)
        let point = CGPoint(x: 0, y: 200)

        // Act
        let result = DropZone.calculate(at: point, in: size)

        // Assert
        #expect(result == .right)
    }

    @Test

    func test_calculate_zeroHeight_returnsRight() {
        // Arrange
        let size = CGSize(width: 400, height: 0)
        let point = CGPoint(x: 200, y: 0)

        // Act
        let result = DropZone.calculate(at: point, in: size)

        // Assert
        #expect(result == .right)
    }

    @Test

    func test_calculate_negativeDimensions_returnsRight() {
        // Arrange
        let size = CGSize(width: -100, height: -100)
        let point = CGPoint.zero

        // Act
        let result = DropZone.calculate(at: point, in: size)

        // Assert
        #expect(result == .right)
    }

    // MARK: - newDirection

    @Test

    func test_newDirection_allCasesMapped() {
        // Assert
        #expect(DropZone.left.newDirection == .left)
        #expect(DropZone.right.newDirection == .right)
    }

    // MARK: - Non-Square Aspect Ratio

    @Test

    func test_calculate_wideContainer_leftRegionLarger() {
        // In a wide container (800x200), left/right regions dominate.
        // Point at (100, 100) — center height, 12.5% from left → left wins.
        // Arrange
        let size = CGSize(width: 800, height: 200)
        let point = CGPoint(x: 100, y: 100)

        // Act
        let result = DropZone.calculate(at: point, in: size)

        // Assert
        #expect(result == .left)
    }

    // MARK: - CaseIterable

    @Test

    func test_caseIterable_hasTwoCases() {
        // Assert
        #expect(DropZone.allCases.count == 2)
    }
}
