import AppKit
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class SplitTreeNavigationTests {

    // MARK: - Next/Previous

    @Test

    func test_nextView_singleView_returnsSelf() {
        // Arrange
        let v1 = MockTerminalView(name: "A")
        let tree = TestSplitTree(view: v1)

        // Act
        let next = tree.nextView(after: v1.id)

        // Assert
        #expect(next?.id == v1.id)
    }

    @Test

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
        #expect(next1?.id == v2.id)
        #expect(next2?.id == v1.id)  // wraps
    }

    @Test

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
        #expect(prev1?.id == v2.id)  // wraps
        #expect(prev2?.id == v1.id)
    }

    @Test

    func test_nextView_threeViews_cyclesCorrectly() throws {
        // Arrange
        let v1 = MockTerminalView(name: "A")
        let v2 = MockTerminalView(name: "B")
        let v3 = MockTerminalView(name: "C")
        var tree = TestSplitTree(view: v1)
        tree = try tree.inserting(view: v2, at: v1, direction: .right)
        tree = try tree.inserting(view: v3, at: v2, direction: .right)

        // Act & Assert
        #expect(tree.nextView(after: v1.id)?.id == v2.id)
        #expect(tree.nextView(after: v2.id)?.id == v3.id)
        #expect(tree.nextView(after: v3.id)?.id == v1.id)
    }

    @Test

    func test_nextView_emptyTree_returnsNil() {
        // Arrange
        let tree = TestSplitTree()

        // Act
        let next = tree.nextView(after: UUID())

        // Assert
        #expect((next) == nil)
    }

    @Test

    func test_nextView_unknownId_returnsNil() {
        // Arrange
        let v1 = MockTerminalView(name: "A")
        let tree = TestSplitTree(view: v1)

        // Act
        let next = tree.nextView(after: UUID())

        // Assert
        #expect((next) == nil)
    }

    // MARK: - Directional Navigation: Horizontal

    @Test

    func test_neighbor_horizontalSplit_leftRight() throws {
        // Arrange: A | B (horizontal split)
        let v1 = MockTerminalView(name: "A")
        let v2 = MockTerminalView(name: "B")
        var tree = TestSplitTree(view: v1)
        tree = try tree.inserting(view: v2, at: v1, direction: .right)

        // Act & Assert
        #expect(tree.neighbor(of: v1.id, direction: .right)?.id == v2.id)
        #expect(tree.neighbor(of: v2.id, direction: .left)?.id == v1.id)
        #expect((tree.neighbor(of: v1.id, direction: .left)) == nil)
        #expect((tree.neighbor(of: v2.id, direction: .right)) == nil)
    }

    // MARK: - Directional Navigation: Vertical

    @Test

    func test_neighbor_verticalSplit_upDown() throws {
        // Arrange: A / B (vertical split, A on top)
        let v1 = MockTerminalView(name: "A")
        let v2 = MockTerminalView(name: "B")
        var tree = TestSplitTree(view: v1)
        tree = try tree.inserting(view: v2, at: v1, direction: .down)

        // Act & Assert
        #expect(tree.neighbor(of: v1.id, direction: .down)?.id == v2.id)
        #expect(tree.neighbor(of: v2.id, direction: .up)?.id == v1.id)
        #expect((tree.neighbor(of: v1.id, direction: .up)) == nil)
        #expect((tree.neighbor(of: v2.id, direction: .down)) == nil)
    }

    // MARK: - Directional Navigation: Cross-axis

    @Test

    func test_neighbor_horizontalSplit_upDown_returnsNil() throws {
        // Arrange: A | B (horizontal split)
        let v1 = MockTerminalView(name: "A")
        let v2 = MockTerminalView(name: "B")
        var tree = TestSplitTree(view: v1)
        tree = try tree.inserting(view: v2, at: v1, direction: .right)

        // Act & Assert — no up/down neighbors in horizontal split
        #expect((tree.neighbor(of: v1.id, direction: .up)) == nil)
        #expect((tree.neighbor(of: v1.id, direction: .down)) == nil)
        #expect((tree.neighbor(of: v2.id, direction: .up)) == nil)
        #expect((tree.neighbor(of: v2.id, direction: .down)) == nil)
    }

    // MARK: - Directional Navigation: Nested Splits

    @Test

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
        #expect(tree.neighbor(of: v1.id, direction: .down)?.id == v3.id)
        #expect(tree.neighbor(of: v3.id, direction: .up)?.id == v1.id)

        // A and B are still horizontal neighbors
        #expect(tree.neighbor(of: v1.id, direction: .right)?.id == v2.id)
    }

    // MARK: - Edge Cases

    @Test

    func test_neighbor_singleView_returnsNil() {
        // Arrange
        let v1 = MockTerminalView(name: "A")
        let tree = TestSplitTree(view: v1)

        // Assert
        #expect((tree.neighbor(of: v1.id, direction: .left)) == nil)
        #expect((tree.neighbor(of: v1.id, direction: .right)) == nil)
        #expect((tree.neighbor(of: v1.id, direction: .up)) == nil)
        #expect((tree.neighbor(of: v1.id, direction: .down)) == nil)
    }

    @Test

    func test_neighbor_emptyTree_returnsNil() {
        // Arrange
        let tree = TestSplitTree()

        // Assert
        #expect((tree.neighbor(of: UUID(), direction: .right)) == nil)
    }

    @Test

    func test_neighbor_unknownId_returnsNil() throws {
        // Arrange
        let v1 = MockTerminalView(name: "A")
        let v2 = MockTerminalView(name: "B")
        var tree = TestSplitTree(view: v1)
        tree = try tree.inserting(view: v2, at: v1, direction: .right)

        // Assert
        #expect((tree.neighbor(of: UUID(), direction: .right)) == nil)
    }
}
