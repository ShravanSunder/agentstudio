import AppKit
import XCTest

@testable import AgentStudio

final class SplitTreeStructuralIdentityTests: XCTestCase {

    // MARK: - Structural Equality

    func test_sameStructure_sameViews_equal() throws {
        // Arrange - two trees built from the same views
        let viewA = MockTerminalView(name: "A")
        let viewB = MockTerminalView(name: "B")

        let tree1 = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)
        let tree2 = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)

        // Act
        let id1 = tree1.root!.structuralIdentity
        let id2 = tree2.root!.structuralIdentity

        // Assert
        XCTAssertEqual(id1, id2)
    }

    func test_differentViews_notEqual() throws {
        // Arrange - same structure but different view instances
        let viewA1 = MockTerminalView(name: "A")
        let viewB1 = MockTerminalView(name: "B")
        let viewA2 = MockTerminalView(name: "A")
        let viewB2 = MockTerminalView(name: "B")

        let tree1 = try TestSplitTree(view: viewA1)
            .inserting(view: viewB1, at: viewA1, direction: .right)
        let tree2 = try TestSplitTree(view: viewA2)
            .inserting(view: viewB2, at: viewA2, direction: .right)

        // Act
        let id1 = tree1.root!.structuralIdentity
        let id2 = tree2.root!.structuralIdentity

        // Assert - different NSView instances → different identity
        XCTAssertNotEqual(id1, id2)
    }

    func test_ratioChange_stillEqual() throws {
        // Arrange - same views, different ratios
        let viewA = MockTerminalView(name: "A")
        let viewB = MockTerminalView(name: "B")

        let tree1 = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)
        let tree2 = tree1.resizing(view: viewA, ratio: 0.3)

        // Act
        let id1 = tree1.root!.structuralIdentity
        let id2 = tree2.root!.structuralIdentity

        // Assert - ratio is excluded from structural identity
        XCTAssertEqual(id1, id2, "Ratio changes should NOT affect structural identity")
    }

    func test_directionChange_notEqual() throws {
        // Arrange - same views but different split directions
        let viewA = MockTerminalView(name: "A")
        let viewB = MockTerminalView(name: "B")

        let horizontalTree = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)  // horizontal
        let verticalTree = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .down)  // vertical

        // Act
        let id1 = horizontalTree.root!.structuralIdentity
        let id2 = verticalTree.root!.structuralIdentity

        // Assert
        XCTAssertNotEqual(id1, id2, "Different directions should have different structural identity")
    }

    // MARK: - Hash Consistency

    func test_hashConsistency() throws {
        // Arrange
        let viewA = MockTerminalView(name: "A")
        let viewB = MockTerminalView(name: "B")

        let tree1 = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)
        let tree2 = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)

        let id1 = tree1.root!.structuralIdentity
        let id2 = tree2.root!.structuralIdentity

        // Assert - equal identities must have equal hashes
        XCTAssertEqual(id1.hashValue, id2.hashValue, "Equal structural identities must have equal hashes")
    }

    func test_hashConsistency_withRatioChange() throws {
        // Arrange - same structure, different ratio
        let viewA = MockTerminalView(name: "A")
        let viewB = MockTerminalView(name: "B")

        let tree1 = try TestSplitTree(view: viewA)
            .inserting(view: viewB, at: viewA, direction: .right)
        let tree2 = tree1.resizing(view: viewA, ratio: 0.7)

        let id1 = tree1.root!.structuralIdentity
        let id2 = tree2.root!.structuralIdentity

        // Assert - ratio excluded, so hashes should match
        XCTAssertEqual(id1.hashValue, id2.hashValue, "Ratio-only changes should produce same hash")
    }

    // MARK: - Leaf Identity

    func test_leafNode_structuralIdentity_usesObjectIdentifier() {
        // Arrange
        let view = MockTerminalView(name: "leaf")
        let tree = TestSplitTree(view: view)

        guard case .leaf = tree.root else {
            XCTFail("Expected leaf node")
            return
        }

        let id1 = tree.root!.structuralIdentity
        let id2 = tree.root!.structuralIdentity

        // Assert - same view instance, same identity
        XCTAssertEqual(id1, id2)
    }

    func test_leafNode_differentInstances_notEqual() {
        // Arrange - two different NSView instances with the same UUID
        let sharedId = UUID()
        let view1 = MockTerminalView(id: sharedId, name: "leaf")
        let view2 = MockTerminalView(id: sharedId, name: "leaf")

        let tree1 = TestSplitTree(view: view1)
        let tree2 = TestSplitTree(view: view2)

        // Assert - structural identity uses object identity (===), not UUID
        XCTAssertNotEqual(
            tree1.root!.structuralIdentity,
            tree2.root!.structuralIdentity,
            "Structural identity should use object identity, not value equality"
        )
    }
}
