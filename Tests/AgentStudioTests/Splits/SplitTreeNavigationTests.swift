import XCTest
import AppKit
@testable import AgentStudio

final class SplitTreeNavigationTests: XCTestCase {

    // MARK: - Next/Previous

    func test_nextView_singleView_returnsSelf() {
        // Arrange
        let v1 = MockTerminalView(name: "A")
        let tree = TestSplitTree(view: v1)

        // Act
        let next = tree.nextView(after: v1.id)

        // Assert
        XCTAssertEqual(next?.id, v1.id)
    }

    func test_nextView_twoViews_wrapsAround() throws {
        // Arrange
        let v1 = MockTerminalView(name: "A")
        let v2 = MockTerminalView(name: "B")
        var tree = TestSplitTree(view: v1)
        tree = try tree.inserting(view: v2, at: v1, direction: .right)

        // Act
        let next1 = tree.nextView(after: v1.id)
        let next2 = tree.nextView(after: v2.id)

        // Assert
        XCTAssertEqual(next1?.id, v2.id)
        XCTAssertEqual(next2?.id, v1.id) // wraps
    }

    func test_previousView_twoViews_wrapsAround() throws {
        // Arrange
        let v1 = MockTerminalView(name: "A")
        let v2 = MockTerminalView(name: "B")
        var tree = TestSplitTree(view: v1)
        tree = try tree.inserting(view: v2, at: v1, direction: .right)

        // Act
        let prev1 = tree.previousView(before: v1.id)
        let prev2 = tree.previousView(before: v2.id)

        // Assert
        XCTAssertEqual(prev1?.id, v2.id) // wraps
        XCTAssertEqual(prev2?.id, v1.id)
    }

    func test_nextView_threeViews_cyclesCorrectly() throws {
        // Arrange
        let v1 = MockTerminalView(name: "A")
        let v2 = MockTerminalView(name: "B")
        let v3 = MockTerminalView(name: "C")
        var tree = TestSplitTree(view: v1)
        tree = try tree.inserting(view: v2, at: v1, direction: .right)
        tree = try tree.inserting(view: v3, at: v2, direction: .right)

        // Act & Assert
        XCTAssertEqual(tree.nextView(after: v1.id)?.id, v2.id)
        XCTAssertEqual(tree.nextView(after: v2.id)?.id, v3.id)
        XCTAssertEqual(tree.nextView(after: v3.id)?.id, v1.id)
    }

    func test_nextView_emptyTree_returnsNil() {
        // Arrange
        let tree = TestSplitTree()

        // Act
        let next = tree.nextView(after: UUID())

        // Assert
        XCTAssertNil(next)
    }

    func test_nextView_unknownId_returnsNil() {
        // Arrange
        let v1 = MockTerminalView(name: "A")
        let tree = TestSplitTree(view: v1)

        // Act
        let next = tree.nextView(after: UUID())

        // Assert
        XCTAssertNil(next)
    }

    // MARK: - Directional Navigation: Horizontal

    func test_neighbor_horizontalSplit_leftRight() throws {
        // Arrange: A | B (horizontal split)
        let v1 = MockTerminalView(name: "A")
        let v2 = MockTerminalView(name: "B")
        var tree = TestSplitTree(view: v1)
        tree = try tree.inserting(view: v2, at: v1, direction: .right)

        // Act & Assert
        XCTAssertEqual(tree.neighbor(of: v1.id, direction: .right)?.id, v2.id)
        XCTAssertEqual(tree.neighbor(of: v2.id, direction: .left)?.id, v1.id)
        XCTAssertNil(tree.neighbor(of: v1.id, direction: .left))
        XCTAssertNil(tree.neighbor(of: v2.id, direction: .right))
    }

    // MARK: - Directional Navigation: Vertical

    func test_neighbor_verticalSplit_upDown() throws {
        // Arrange: A / B (vertical split, A on top)
        let v1 = MockTerminalView(name: "A")
        let v2 = MockTerminalView(name: "B")
        var tree = TestSplitTree(view: v1)
        tree = try tree.inserting(view: v2, at: v1, direction: .down)

        // Act & Assert
        XCTAssertEqual(tree.neighbor(of: v1.id, direction: .down)?.id, v2.id)
        XCTAssertEqual(tree.neighbor(of: v2.id, direction: .up)?.id, v1.id)
        XCTAssertNil(tree.neighbor(of: v1.id, direction: .up))
        XCTAssertNil(tree.neighbor(of: v2.id, direction: .down))
    }

    // MARK: - Directional Navigation: Cross-axis

    func test_neighbor_horizontalSplit_upDown_returnsNil() throws {
        // Arrange: A | B (horizontal split)
        let v1 = MockTerminalView(name: "A")
        let v2 = MockTerminalView(name: "B")
        var tree = TestSplitTree(view: v1)
        tree = try tree.inserting(view: v2, at: v1, direction: .right)

        // Act & Assert — no up/down neighbors in horizontal split
        XCTAssertNil(tree.neighbor(of: v1.id, direction: .up))
        XCTAssertNil(tree.neighbor(of: v1.id, direction: .down))
        XCTAssertNil(tree.neighbor(of: v2.id, direction: .up))
        XCTAssertNil(tree.neighbor(of: v2.id, direction: .down))
    }

    // MARK: - Directional Navigation: Nested Splits

    func test_neighbor_nestedSplit_findsAcrossLevels() throws {
        // Arrange: (A | B) / C — A and B side by side on top, C on bottom
        let v1 = MockTerminalView(name: "A")
        let v2 = MockTerminalView(name: "B")
        let v3 = MockTerminalView(name: "C")
        var tree = TestSplitTree(view: v1)
        tree = try tree.inserting(view: v2, at: v1, direction: .right)
        // Now insert C below v1 — this creates a vertical split around the existing horizontal
        tree = try tree.inserting(view: v3, at: v1, direction: .down)

        // A is above C in the nested structure
        XCTAssertEqual(tree.neighbor(of: v1.id, direction: .down)?.id, v3.id)
        XCTAssertEqual(tree.neighbor(of: v3.id, direction: .up)?.id, v1.id)

        // A and B are still horizontal neighbors
        XCTAssertEqual(tree.neighbor(of: v1.id, direction: .right)?.id, v2.id)
    }

    // MARK: - Edge Cases

    func test_neighbor_singleView_returnsNil() {
        // Arrange
        let v1 = MockTerminalView(name: "A")
        let tree = TestSplitTree(view: v1)

        // Assert
        XCTAssertNil(tree.neighbor(of: v1.id, direction: .left))
        XCTAssertNil(tree.neighbor(of: v1.id, direction: .right))
        XCTAssertNil(tree.neighbor(of: v1.id, direction: .up))
        XCTAssertNil(tree.neighbor(of: v1.id, direction: .down))
    }

    func test_neighbor_emptyTree_returnsNil() {
        // Arrange
        let tree = TestSplitTree()

        // Assert
        XCTAssertNil(tree.neighbor(of: UUID(), direction: .right))
    }

    func test_neighbor_unknownId_returnsNil() throws {
        // Arrange
        let v1 = MockTerminalView(name: "A")
        let v2 = MockTerminalView(name: "B")
        var tree = TestSplitTree(view: v1)
        tree = try tree.inserting(view: v2, at: v1, direction: .right)

        // Assert
        XCTAssertNil(tree.neighbor(of: UUID(), direction: .right))
    }
}
