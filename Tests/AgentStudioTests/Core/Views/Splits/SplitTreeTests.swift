import AppKit
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
final class SplitTreeTests {

    // MARK: - Initialization

    @Test

    func test_emptyTree_isEmpty() {
        // Arrange
        let tree = TestSplitTree()

        // Assert
        #expect(tree.isEmpty)
        #expect(!(tree.isSplit))
        #expect(tree.allViews.isEmpty)
        #expect((tree.root) == nil)
    }

    @Test

    func test_singleView_properties() {
        // Arrange
        let view = MockTerminalView(name: "alpha")
        let tree = TestSplitTree(view: view)

        // Assert
        #expect(!(tree.isEmpty))
        #expect(!(tree.isSplit))
        #expect(tree.allViews.count == 1)
        #expect(tree.allViews[0] === view)
    }

    // MARK: - Find

    @Test

    func test_find_existingId_returnsView() {
        // Arrange
        let view = MockTerminalView(name: "target")
        let tree = TestSplitTree(view: view)

        // Act
        let found = tree.find(id: view.id)

        // Assert
        #expect(found === view)
    }

    @Test

    func test_find_nonExistentId_returnsNil() {
        // Arrange
        let view = MockTerminalView(name: "target")
        let tree = TestSplitTree(view: view)

        // Act
        let found = tree.find(id: UUID())

        // Assert
        #expect((found) == nil)
    }

    @Test

    func test_find_inEmptyTree_returnsNil() {
        // Arrange
        let tree = TestSplitTree()

        // Act
        let found = tree.find(id: UUID())

        // Assert
        #expect((found) == nil)
    }

    // MARK: - Insert

    @Test

    func test_insert_right_createsSplit() throws {
        // Arrange
        let existing = MockTerminalView(name: "existing")
        let newView = MockTerminalView(name: "new")
        let tree = TestSplitTree(view: existing)

        // Act
        let result = try tree.inserting(view: newView, at: existing, direction: .right)

        // Assert
        #expect(result.isSplit)
        #expect(result.allViews.count == 2)
        // Existing should be on left, new on right
        #expect(result.allViews[0] === existing)
        #expect(result.allViews[1] === newView)

        guard case .split(let split) = result.root else {
            Issue.record("Expected split node")
            return
        }
        #expect(split.direction == .horizontal)
        #expect(split.ratio == 0.5)
    }

    @Test

    func test_insert_left_createsSplit() throws {
        // Arrange
        let existing = MockTerminalView(name: "existing")
        let newView = MockTerminalView(name: "new")
        let tree = TestSplitTree(view: existing)

        // Act
        let result = try tree.inserting(view: newView, at: existing, direction: .left)

        // Assert
        #expect(result.allViews.count == 2)
        // New should be on left, existing on right
        #expect(result.allViews[0] === newView)
        #expect(result.allViews[1] === existing)

        guard case .split(let split) = result.root else {
            Issue.record("Expected split node")
            return
        }
        #expect(split.direction == .horizontal)
    }

    @Test

    func test_insert_up_createsVerticalSplit() throws {
        // Arrange
        let existing = MockTerminalView(name: "existing")
        let newView = MockTerminalView(name: "new")
        let tree = TestSplitTree(view: existing)

        // Act
        let result = try tree.inserting(view: newView, at: existing, direction: .up)

        // Assert
        guard case .split(let split) = result.root else {
            Issue.record("Expected split node")
            return
        }
        #expect(split.direction == .vertical)
        // New on top (left), existing on bottom (right)
        #expect(result.allViews[0] === newView)
        #expect(result.allViews[1] === existing)
    }

    @Test

    func test_insert_down_createsVerticalSplit() throws {
        // Arrange
        let existing = MockTerminalView(name: "existing")
        let newView = MockTerminalView(name: "new")
        let tree = TestSplitTree(view: existing)

        // Act
        let result = try tree.inserting(view: newView, at: existing, direction: .down)

        // Assert
        guard case .split(let split) = result.root else {
            Issue.record("Expected split node")
            return
        }
        #expect(split.direction == .vertical)
        // Existing on top (left), new on bottom (right)
        #expect(result.allViews[0] === existing)
        #expect(result.allViews[1] === newView)
    }

    @Test

    func test_insert_intoEmptyTree_throws() {
        // Arrange
        let tree = TestSplitTree()
        let target = MockTerminalView(name: "target")
        let newView = MockTerminalView(name: "new")

        // Act & Assert
        #expect(throws: Error.self) {
            _ = try tree.inserting(view: newView, at: target, direction: .right)
        }
    }

    @Test

    func test_insert_targetNotFound_throws() {
        // Arrange
        let existing = MockTerminalView(name: "existing")
        let wrongTarget = MockTerminalView(name: "wrong")
        let newView = MockTerminalView(name: "new")
        let tree = TestSplitTree(view: existing)

        // Act & Assert
        #expect(throws: Error.self) {
            _ = try tree.inserting(view: newView, at: wrongTarget, direction: .right)
        }
    }

    @Test

    func test_insert_nested_createsDeepTree() throws {
        // Arrange - start with A | B
        let viewA = MockTerminalView(name: "A")
        let viewB = MockTerminalView(name: "B")
        let viewC = MockTerminalView(name: "C")
        let tree = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)

        // Act - insert C below B
        let result = try tree.inserting(view: viewC, at: viewB, direction: .down)

        // Assert - should have 3 views: A, B, C
        #expect(result.allViews.count == 3)
        #expect(result.allViews[0] === viewA)
        #expect(result.allViews[1] === viewB)
        #expect(result.allViews[2] === viewC)

        // Root should still be horizontal split
        guard case .split(let rootSplit) = result.root else {
            Issue.record("Expected split root")
            return
        }
        #expect(rootSplit.direction == .horizontal)

        // Right child should be a vertical split (B above C)
        guard case .split(let rightSplit) = rootSplit.right else {
            Issue.record("Expected nested split")
            return
        }
        #expect(rightSplit.direction == .vertical)
    }

    // MARK: - Remove

    @Test

    func test_remove_singleView_returnsNil() {
        // Arrange
        let view = MockTerminalView(name: "only")
        let tree = TestSplitTree(view: view)

        // Act
        let result = tree.removing(view: view)

        // Assert
        #expect((result) == nil)
    }

    @Test

    func test_remove_fromSplit_collapsesToLeaf() throws {
        // Arrange - A | B
        let viewA = MockTerminalView(name: "A")
        let viewB = MockTerminalView(name: "B")
        let tree = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)

        // Act - remove A
        let result = tree.removing(view: viewA)

        // Assert - should collapse to just B
        #expect((result) != nil)
        #expect(!(result!.isSplit))
        #expect(result!.allViews.count == 1)
        #expect(result!.allViews[0] === viewB)
    }

    @Test

    func test_remove_nonExistent_returnsUnchanged() {
        // Arrange
        let view = MockTerminalView(name: "existing")
        let stranger = MockTerminalView(name: "stranger")
        let tree = TestSplitTree(view: view)

        // Act
        let result = tree.removing(view: stranger)

        // Assert - tree should still have the original view
        #expect((result) != nil)
        #expect(result!.allViews.count == 1)
        #expect(result!.allViews[0] === view)
    }

    @Test

    func test_remove_fromDeepTree_preservesOtherBranches() throws {
        // Arrange - A | (B / C)
        let viewA = MockTerminalView(name: "A")
        let viewB = MockTerminalView(name: "B")
        let viewC = MockTerminalView(name: "C")
        let tree = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)
            .inserting(view: viewC, at: viewB, direction: .down)

        // Act - remove C
        let result = tree.removing(view: viewC)

        // Assert - should have A | B (still split)
        #expect((result) != nil)
        #expect(result!.isSplit)
        #expect(result!.allViews.count == 2)
        #expect(result!.allViews[0] === viewA)
        #expect(result!.allViews[1] === viewB)
    }

    @Test

    func test_remove_fromEmptyTree_returnsNil() {
        // Arrange
        let tree = TestSplitTree()
        let view = MockTerminalView(name: "orphan")

        // Act
        let result = tree.removing(view: view)

        // Assert
        #expect((result) == nil)
    }

    // MARK: - Resize

    @Test

    func test_resize_clampsRatio() throws {
        // Arrange
        let viewA = MockTerminalView(name: "A")
        let viewB = MockTerminalView(name: "B")
        let tree = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)

        // Act - try to resize beyond bounds
        let tooSmall = tree.resizing(view: viewA, ratio: 0.0)
        let tooLarge = tree.resizing(view: viewA, ratio: 1.0)

        // Assert - should be clamped to 0.1 and 0.9
        guard case .split(let smallSplit) = tooSmall.root else {
            Issue.record("Expected split")
            return
        }
        #expect(abs((smallSplit.ratio) - (0.1)) <= 0.001)

        guard case .split(let largeSplit) = tooLarge.root else {
            Issue.record("Expected split")
            return
        }
        #expect(abs((largeSplit.ratio) - (0.9)) <= 0.001)
    }

    @Test

    func test_resize_updatesCorrectSplit() throws {
        // Arrange - A | (B / C) with root ratio 0.5 and nested ratio 0.5
        let viewA = MockTerminalView(name: "A")
        let viewB = MockTerminalView(name: "B")
        let viewC = MockTerminalView(name: "C")
        let tree = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)
            .inserting(view: viewC, at: viewB, direction: .down)

        // Act - resize the nested split (containing B)
        let result = tree.resizing(view: viewB, ratio: 0.3)

        // Assert - root ratio should still be 0.5, nested should be 0.3
        guard case .split(let rootSplit) = result.root else {
            Issue.record("Expected root split")
            return
        }
        #expect(abs((rootSplit.ratio) - (0.5)) <= 0.001, "Root ratio should be unchanged")

        guard case .split(let nestedSplit) = rootSplit.right else {
            Issue.record("Expected nested split")
            return
        }
        #expect(abs((nestedSplit.ratio) - (0.3)) <= 0.001, "Nested ratio should be 0.3")
    }

    // MARK: - Equalize

    @Test

    func test_equalize_setsAllRatiosToHalf() throws {
        // Arrange - create tree with non-0.5 ratios
        let viewA = MockTerminalView(name: "A")
        let viewB = MockTerminalView(name: "B")
        let viewC = MockTerminalView(name: "C")
        let tree = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)
            .inserting(view: viewC, at: viewB, direction: .down)
            .resizing(view: viewA, ratio: 0.3)
            .resizing(view: viewB, ratio: 0.7)

        // Act
        let equalized = tree.equalized()

        // Assert - all ratios should be 0.5
        guard case .split(let rootSplit) = equalized.root else {
            Issue.record("Expected root split")
            return
        }
        #expect(abs((rootSplit.ratio) - (0.5)) <= 0.001)

        guard case .split(let nestedSplit) = rootSplit.right else {
            Issue.record("Expected nested split")
            return
        }
        #expect(abs((nestedSplit.ratio) - (0.5)) <= 0.001)
    }

    // MARK: - allViews Ordering

    @Test

    func test_allViews_orderedLeftToRight() throws {
        // Arrange - (A | B) with A on left, B on right
        let viewA = MockTerminalView(name: "A")
        let viewB = MockTerminalView(name: "B")
        let tree = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)

        // Assert
        #expect(tree.allViews.count == 2)
        #expect(tree.allViews[0] === viewA)
        #expect(tree.allViews[1] === viewB)
    }

    @Test

    func test_allViews_deepTree_orderedCorrectly() throws {
        // Arrange - (A | (B / C))
        let viewA = MockTerminalView(name: "A")
        let viewB = MockTerminalView(name: "B")
        let viewC = MockTerminalView(name: "C")
        let tree = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)
            .inserting(view: viewC, at: viewB, direction: .down)

        // Assert - order: A (left), B (right-left), C (right-right)
        #expect(tree.allViews.count == 3)
        #expect(tree.allViews[0] === viewA)
        #expect(tree.allViews[1] === viewB)
        #expect(tree.allViews[2] === viewC)
    }

    // MARK: - Contains

    @Test

    func test_contains_findsNestedViews() throws {
        // Arrange
        let viewA = MockTerminalView(name: "A")
        let viewB = MockTerminalView(name: "B")
        let viewC = MockTerminalView(name: "C")
        let tree = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)
            .inserting(view: viewC, at: viewB, direction: .down)

        // Assert
        #expect((tree.find(id: viewA.id)) != nil)
        #expect((tree.find(id: viewB.id)) != nil)
        #expect((tree.find(id: viewC.id)) != nil)
        #expect((tree.find(id: UUID())) == nil)
    }

    // MARK: - Sequence

    @Test

    func test_sequence_iteratesAllViews() throws {
        // Arrange
        let viewA = MockTerminalView(name: "A")
        let viewB = MockTerminalView(name: "B")
        let tree = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)

        // Act
        let views = Array(tree)

        // Assert
        #expect(views.count == 2)
        #expect(views[0] === viewA)
        #expect(views[1] === viewB)
    }
}
