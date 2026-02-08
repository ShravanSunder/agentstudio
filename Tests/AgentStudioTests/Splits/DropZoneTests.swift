import XCTest
import CoreGraphics
@testable import AgentStudio

final class DropZoneTests: XCTestCase {

    // MARK: - Edge Proximity Detection

    func test_calculate_nearLeftEdge_returnsLeft() {
        // Arrange
        let size = CGSize(width: 400, height: 400)
        let point = CGPoint(x: 10, y: 200)

        // Act
        let result = DropZone.calculate(at: point, in: size)

        // Assert
        XCTAssertEqual(result, .left)
    }

    func test_calculate_nearRightEdge_returnsRight() {
        // Arrange
        let size = CGSize(width: 400, height: 400)
        let point = CGPoint(x: 390, y: 200)

        // Act
        let result = DropZone.calculate(at: point, in: size)

        // Assert
        XCTAssertEqual(result, .right)
    }

    func test_calculate_nearTopEdge_returnsTop() {
        // Arrange
        let size = CGSize(width: 400, height: 400)
        let point = CGPoint(x: 200, y: 10)

        // Act
        let result = DropZone.calculate(at: point, in: size)

        // Assert
        XCTAssertEqual(result, .top)
    }

    func test_calculate_nearBottomEdge_returnsBottom() {
        // Arrange
        let size = CGSize(width: 400, height: 400)
        let point = CGPoint(x: 200, y: 390)

        // Act
        let result = DropZone.calculate(at: point, in: size)

        // Assert
        XCTAssertEqual(result, .bottom)
    }

    // MARK: - Tie-Breaking

    func test_calculate_topLeftCorner_returnsLeft() {
        // At (0, 0): distToLeft=0, distToTop=0. Left wins (checked first in if-chain).
        // Arrange
        let size = CGSize(width: 400, height: 400)
        let point = CGPoint(x: 0, y: 0)

        // Act
        let result = DropZone.calculate(at: point, in: size)

        // Assert
        XCTAssertEqual(result, .left)
    }

    func test_calculate_exactCenter_returnsLeft() {
        // All distances equal (0.5). Left wins (checked first in if-chain).
        // Arrange
        let size = CGSize(width: 400, height: 400)
        let point = CGPoint(x: 200, y: 200)

        // Act
        let result = DropZone.calculate(at: point, in: size)

        // Assert
        XCTAssertEqual(result, .left)
    }

    // MARK: - Degenerate Sizes

    func test_calculate_zeroWidth_returnsRight() {
        // Arrange
        let size = CGSize(width: 0, height: 400)
        let point = CGPoint(x: 0, y: 200)

        // Act
        let result = DropZone.calculate(at: point, in: size)

        // Assert
        XCTAssertEqual(result, .right)
    }

    func test_calculate_zeroHeight_returnsRight() {
        // Arrange
        let size = CGSize(width: 400, height: 0)
        let point = CGPoint(x: 200, y: 0)

        // Act
        let result = DropZone.calculate(at: point, in: size)

        // Assert
        XCTAssertEqual(result, .right)
    }

    func test_calculate_negativeDimensions_returnsRight() {
        // Arrange
        let size = CGSize(width: -100, height: -100)
        let point = CGPoint(x: 0, y: 0)

        // Act
        let result = DropZone.calculate(at: point, in: size)

        // Assert
        XCTAssertEqual(result, .right)
    }

    // MARK: - splitDirection

    func test_splitDirection_leftRight_horizontal() {
        // Assert
        XCTAssertEqual(DropZone.left.splitDirection, .horizontal)
        XCTAssertEqual(DropZone.right.splitDirection, .horizontal)
    }

    func test_splitDirection_topBottom_vertical() {
        // Assert
        XCTAssertEqual(DropZone.top.splitDirection, .vertical)
        XCTAssertEqual(DropZone.bottom.splitDirection, .vertical)
    }

    // MARK: - newDirection

    func test_newDirection_allCasesMapped() {
        // Assert
        XCTAssertEqual(DropZone.left.newDirection, .left)
        XCTAssertEqual(DropZone.right.newDirection, .right)
        XCTAssertEqual(DropZone.top.newDirection, .up)
        XCTAssertEqual(DropZone.bottom.newDirection, .down)
    }

    // MARK: - Non-Square Aspect Ratio

    func test_calculate_wideContainer_leftRegionLarger() {
        // In a wide container (800x200), left/right regions dominate.
        // Point at (100, 100) — center height, 12.5% from left → left wins.
        // Arrange
        let size = CGSize(width: 800, height: 200)
        let point = CGPoint(x: 100, y: 100)

        // Act
        let result = DropZone.calculate(at: point, in: size)

        // Assert
        XCTAssertEqual(result, .left)
    }

    // MARK: - CaseIterable

    func test_caseIterable_hasFourCases() {
        // Assert
        XCTAssertEqual(DropZone.allCases.count, 4)
    }
}
