import AppKit
import XCTest

@testable import AgentStudio

final class SplitTreeTests: XCTestCase {

    // MARK: - Initialization

    func test_emptyTree_isEmpty() {
        // Arrange
        let tree = TestSplitTree()

        // Assert
        XCTAssertTrue(tree.isEmpty)
        XCTAssertFalse(tree.isSplit)
        XCTAssertTrue(tree.allViews.isEmpty)
        XCTAssertNil(tree.root)
    }

    func test_singleView_properties() {
        // Arrange
        let view = MockTerminalView(name: "alpha")
        let tree = TestSplitTree(view: view)

        // Assert
        XCTAssertFalse(tree.isEmpty)
        XCTAssertFalse(tree.isSplit)
        XCTAssertEqual(tree.allViews.count, 1)
        XCTAssertTrue(tree.allViews[0] === view)
    }

    // MARK: - Find

    func test_find_existingId_returnsView() {
        // Arrange
        let view = MockTerminalView(name: "target")
        let tree = TestSplitTree(view: view)

        // Act
        let found = tree.find(id: view.id)

        // Assert
        XCTAssertTrue(found === view)
    }

    func test_find_nonExistentId_returnsNil() {
        // Arrange
        let view = MockTerminalView(name: "target")
        let tree = TestSplitTree(view: view)

        // Act
        let found = tree.find(id: UUID())

        // Assert
        XCTAssertNil(found)
    }

    func test_find_inEmptyTree_returnsNil() {
        // Arrange
        let tree = TestSplitTree()

        // Act
        let found = tree.find(id: UUID())

        // Assert
        XCTAssertNil(found)
    }

    // MARK: - Insert

    func test_insert_right_createsSplit() throws {
        // Arrange
        let existing = MockTerminalView(name: "existing")
        let newView = MockTerminalView(name: "new")
        let tree = TestSplitTree(view: existing)

        // Act
        let result = try tree.inserting(view: newView, at: existing, direction: .right)

        // Assert
        XCTAssertTrue(result.isSplit)
        XCTAssertEqual(result.allViews.count, 2)
        // Existing should be on left, new on right
        XCTAssertTrue(result.allViews[0] === existing)
        XCTAssertTrue(result.allViews[1] === newView)

        guard case .split(let split) = result.root else {
            XCTFail("Expected split node")
            return
        }
        XCTAssertEqual(split.direction, .horizontal)
        XCTAssertEqual(split.ratio, 0.5)
    }

    func test_insert_left_createsSplit() throws {
        // Arrange
        let existing = MockTerminalView(name: "existing")
        let newView = MockTerminalView(name: "new")
        let tree = TestSplitTree(view: existing)

        // Act
        let result = try tree.inserting(view: newView, at: existing, direction: .left)

        // Assert
        XCTAssertEqual(result.allViews.count, 2)
        // New should be on left, existing on right
        XCTAssertTrue(result.allViews[0] === newView)
        XCTAssertTrue(result.allViews[1] === existing)

        guard case .split(let split) = result.root else {
            XCTFail("Expected split node")
            return
        }
        XCTAssertEqual(split.direction, .horizontal)
    }

    func test_insert_up_createsVerticalSplit() throws {
        // Arrange
        let existing = MockTerminalView(name: "existing")
        let newView = MockTerminalView(name: "new")
        let tree = TestSplitTree(view: existing)

        // Act
        let result = try tree.inserting(view: newView, at: existing, direction: .up)

        // Assert
        guard case .split(let split) = result.root else {
            XCTFail("Expected split node")
            return
        }
        XCTAssertEqual(split.direction, .vertical)
        // New on top (left), existing on bottom (right)
        XCTAssertTrue(result.allViews[0] === newView)
        XCTAssertTrue(result.allViews[1] === existing)
    }

    func test_insert_down_createsVerticalSplit() throws {
        // Arrange
        let existing = MockTerminalView(name: "existing")
        let newView = MockTerminalView(name: "new")
        let tree = TestSplitTree(view: existing)

        // Act
        let result = try tree.inserting(view: newView, at: existing, direction: .down)

        // Assert
        guard case .split(let split) = result.root else {
            XCTFail("Expected split node")
            return
        }
        XCTAssertEqual(split.direction, .vertical)
        // Existing on top (left), new on bottom (right)
        XCTAssertTrue(result.allViews[0] === existing)
        XCTAssertTrue(result.allViews[1] === newView)
    }

    func test_insert_intoEmptyTree_throws() {
        // Arrange
        let tree = TestSplitTree()
        let target = MockTerminalView(name: "target")
        let newView = MockTerminalView(name: "new")

        // Act & Assert
        XCTAssertThrowsError(try tree.inserting(view: newView, at: target, direction: .right))
    }

    func test_insert_targetNotFound_throws() {
        // Arrange
        let existing = MockTerminalView(name: "existing")
        let wrongTarget = MockTerminalView(name: "wrong")
        let newView = MockTerminalView(name: "new")
        let tree = TestSplitTree(view: existing)

        // Act & Assert
        XCTAssertThrowsError(try tree.inserting(view: newView, at: wrongTarget, direction: .right))
    }

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
        XCTAssertEqual(result.allViews.count, 3)
        XCTAssertTrue(result.allViews[0] === viewA)
        XCTAssertTrue(result.allViews[1] === viewB)
        XCTAssertTrue(result.allViews[2] === viewC)

        // Root should still be horizontal split
        guard case .split(let rootSplit) = result.root else {
            XCTFail("Expected split root")
            return
        }
        XCTAssertEqual(rootSplit.direction, .horizontal)

        // Right child should be a vertical split (B above C)
        guard case .split(let rightSplit) = rootSplit.right else {
            XCTFail("Expected nested split")
            return
        }
        XCTAssertEqual(rightSplit.direction, .vertical)
    }

    // MARK: - Remove

    func test_remove_singleView_returnsNil() {
        // Arrange
        let view = MockTerminalView(name: "only")
        let tree = TestSplitTree(view: view)

        // Act
        let result = tree.removing(view: view)

        // Assert
        XCTAssertNil(result)
    }

    func test_remove_fromSplit_collapsesToLeaf() throws {
        // Arrange - A | B
        let viewA = MockTerminalView(name: "A")
        let viewB = MockTerminalView(name: "B")
        let tree = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)

        // Act - remove A
        let result = tree.removing(view: viewA)

        // Assert - should collapse to just B
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isSplit)
        XCTAssertEqual(result!.allViews.count, 1)
        XCTAssertTrue(result!.allViews[0] === viewB)
    }

    func test_remove_nonExistent_returnsUnchanged() {
        // Arrange
        let view = MockTerminalView(name: "existing")
        let stranger = MockTerminalView(name: "stranger")
        let tree = TestSplitTree(view: view)

        // Act
        let result = tree.removing(view: stranger)

        // Assert - tree should still have the original view
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.allViews.count, 1)
        XCTAssertTrue(result!.allViews[0] === view)
    }

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
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isSplit)
        XCTAssertEqual(result!.allViews.count, 2)
        XCTAssertTrue(result!.allViews[0] === viewA)
        XCTAssertTrue(result!.allViews[1] === viewB)
    }

    func test_remove_fromEmptyTree_returnsNil() {
        // Arrange
        let tree = TestSplitTree()
        let view = MockTerminalView(name: "orphan")

        // Act
        let result = tree.removing(view: view)

        // Assert
        XCTAssertNil(result)
    }

    // MARK: - Resize

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
            XCTFail("Expected split")
            return
        }
        XCTAssertEqual(smallSplit.ratio, 0.1, accuracy: 0.001)

        guard case .split(let largeSplit) = tooLarge.root else {
            XCTFail("Expected split")
            return
        }
        XCTAssertEqual(largeSplit.ratio, 0.9, accuracy: 0.001)
    }

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
            XCTFail("Expected root split")
            return
        }
        XCTAssertEqual(rootSplit.ratio, 0.5, accuracy: 0.001, "Root ratio should be unchanged")

        guard case .split(let nestedSplit) = rootSplit.right else {
            XCTFail("Expected nested split")
            return
        }
        XCTAssertEqual(nestedSplit.ratio, 0.3, accuracy: 0.001, "Nested ratio should be 0.3")
    }

    // MARK: - Equalize

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
            XCTFail("Expected root split")
            return
        }
        XCTAssertEqual(rootSplit.ratio, 0.5, accuracy: 0.001)

        guard case .split(let nestedSplit) = rootSplit.right else {
            XCTFail("Expected nested split")
            return
        }
        XCTAssertEqual(nestedSplit.ratio, 0.5, accuracy: 0.001)
    }

    // MARK: - allViews Ordering

    func test_allViews_orderedLeftToRight() throws {
        // Arrange - (A | B) with A on left, B on right
        let viewA = MockTerminalView(name: "A")
        let viewB = MockTerminalView(name: "B")
        let tree = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)

        // Assert
        XCTAssertEqual(tree.allViews.count, 2)
        XCTAssertTrue(tree.allViews[0] === viewA, "First should be left (A)")
        XCTAssertTrue(tree.allViews[1] === viewB, "Second should be right (B)")
    }

    func test_allViews_deepTree_orderedCorrectly() throws {
        // Arrange - (A | (B / C))
        let viewA = MockTerminalView(name: "A")
        let viewB = MockTerminalView(name: "B")
        let viewC = MockTerminalView(name: "C")
        let tree = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)
            .inserting(view: viewC, at: viewB, direction: .down)

        // Assert - order: A (left), B (right-left), C (right-right)
        XCTAssertEqual(tree.allViews.count, 3)
        XCTAssertTrue(tree.allViews[0] === viewA)
        XCTAssertTrue(tree.allViews[1] === viewB)
        XCTAssertTrue(tree.allViews[2] === viewC)
    }

    // MARK: - Contains

    func test_contains_findsNestedViews() throws {
        // Arrange
        let viewA = MockTerminalView(name: "A")
        let viewB = MockTerminalView(name: "B")
        let viewC = MockTerminalView(name: "C")
        let tree = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)
            .inserting(view: viewC, at: viewB, direction: .down)

        // Assert
        XCTAssertNotNil(tree.find(id: viewA.id))
        XCTAssertNotNil(tree.find(id: viewB.id))
        XCTAssertNotNil(tree.find(id: viewC.id))
        XCTAssertNil(tree.find(id: UUID()))
    }

    // MARK: - Sequence

    func test_sequence_iteratesAllViews() throws {
        // Arrange
        let viewA = MockTerminalView(name: "A")
        let viewB = MockTerminalView(name: "B")
        let tree = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)

        // Act
        let views = Array(tree)

        // Assert
        XCTAssertEqual(views.count, 2)
        XCTAssertTrue(views[0] === viewA)
        XCTAssertTrue(views[1] === viewB)
    }
}
