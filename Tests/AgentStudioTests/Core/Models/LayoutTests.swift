import Testing
import Foundation

@testable import AgentStudio

@Suite(.serialized)
final class LayoutTests {

    // MARK: - Initialization

    @Test

    func test_emptyLayout_isEmpty() {
        // Arrange
        let layout = Layout()

        // Assert
        #expect(layout.isEmpty)
        #expect(!(layout.isSplit))
        #expect(layout.paneIds.isEmpty)
        #expect((layout.root) == nil)
    }

    @Test

    func test_singlePane_properties() {
        // Arrange
        let paneId = UUID()
        let layout = Layout(paneId: paneId)

        // Assert
        #expect(!(layout.isEmpty))
        #expect(!(layout.isSplit))
        #expect(layout.paneIds == [paneId])
    }

    // MARK: - Contains

    @Test

    func test_contains_existingPane_returnsTrue() {
        // Arrange
        let paneId = UUID()
        let layout = Layout(paneId: paneId)

        // Assert
        #expect(layout.contains(paneId))
    }

    @Test

    func test_contains_nonExistent_returnsFalse() {
        // Arrange
        let layout = Layout(paneId: UUID())

        // Assert
        #expect(!(layout.contains(UUID())))
    }

    @Test

    func test_contains_emptyLayout_returnsFalse() {
        // Arrange
        let layout = Layout()

        // Assert
        #expect(!(layout.contains(UUID())))
    }

    // MARK: - Insert

    @Test

    func test_insert_after_createsSplit() {
        // Arrange
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)

        // Act
        let result = layout.inserting(
            paneId: paneB, at: paneA,
            direction: .horizontal, position: .after
        )

        // Assert
        #expect(result.isSplit)
        #expect(result.paneIds.count == 2)
        #expect(result.paneIds[0] == paneA)
        #expect(result.paneIds[1] == paneB)

        guard case .split(let split) = result.root else {
            Issue.record("Expected split node")
            return
        }
        #expect(split.direction == .horizontal)
        #expect(abs((split.ratio) - (0.5)) <= 0.001)
    }

    @Test

    func test_insert_before_createsSplit() {
        // Arrange
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)

        // Act
        let result = layout.inserting(
            paneId: paneB, at: paneA,
            direction: .horizontal, position: .before
        )

        // Assert
        #expect(result.paneIds.count == 2)
        #expect(result.paneIds[0] == paneB)
        #expect(result.paneIds[1] == paneA)
    }

    @Test

    func test_insert_vertical_after() {
        // Arrange
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)

        // Act
        let result = layout.inserting(
            paneId: paneB, at: paneA,
            direction: .vertical, position: .after
        )

        // Assert
        guard case .split(let split) = result.root else {
            Issue.record("Expected split node")
            return
        }
        #expect(split.direction == .vertical)
        #expect(result.paneIds[0] == paneA)
        #expect(result.paneIds[1] == paneB)
    }

    @Test

    func test_insert_vertical_before() {
        // Arrange
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)

        // Act
        let result = layout.inserting(
            paneId: paneB, at: paneA,
            direction: .vertical, position: .before
        )

        // Assert
        #expect(result.paneIds[0] == paneB)
        #expect(result.paneIds[1] == paneA)
    }

    @Test

    func test_insert_targetNotFound_returnsUnchanged() {
        // Arrange
        let paneA = UUID()
        let layout = Layout(paneId: paneA)

        // Act
        let result = layout.inserting(
            paneId: UUID(), at: UUID(),
            direction: .horizontal, position: .after
        )

        // Assert
        #expect(result.paneIds == [paneA])
    }

    @Test

    func test_insert_nested_createsDeepTree() {
        // Arrange — A | B
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)

        // Act — insert C below B
        let result = layout.inserting(
            paneId: paneC, at: paneB,
            direction: .vertical, position: .after
        )

        // Assert — should have 3 panes: A, B, C
        #expect(result.paneIds == [paneA, paneB, paneC])

        guard case .split(let rootSplit) = result.root else {
            Issue.record("Expected split root")
            return
        }
        #expect(rootSplit.direction == .horizontal)

        guard case .split(let rightSplit) = rootSplit.right else {
            Issue.record("Expected nested split")
            return
        }
        #expect(rightSplit.direction == .vertical)
    }

    @Test

    func test_insert_intoEmptyLayout_returnsUnchanged() {
        // Arrange
        let layout = Layout()

        // Act
        let result = layout.inserting(
            paneId: UUID(), at: UUID(),
            direction: .horizontal, position: .after
        )

        // Assert
        #expect(result.isEmpty)
    }

    // MARK: - Remove

    @Test

    func test_remove_singlePane_returnsNil() {
        // Arrange
        let paneId = UUID()
        let layout = Layout(paneId: paneId)

        // Act
        let result = layout.removing(paneId: paneId)

        // Assert
        #expect((result) == nil)
    }

    @Test

    func test_remove_fromSplit_collapsesToLeaf() {
        // Arrange — A | B
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)

        // Act — remove A
        let result = layout.removing(paneId: paneA)

        // Assert — should collapse to just B
        #expect((result) != nil)
        #expect(!(result!.isSplit))
        #expect(result!.paneIds == [paneB])
    }

    @Test

    func test_remove_nonExistent_returnsUnchanged() {
        // Arrange
        let paneA = UUID()
        let layout = Layout(paneId: paneA)

        // Act
        let result = layout.removing(paneId: UUID())

        // Assert
        #expect((result) != nil)
        #expect(result!.paneIds == [paneA])
    }

    @Test

    func test_remove_fromDeepTree_preservesOtherBranches() {
        // Arrange — A | (B / C)
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)
            .inserting(paneId: paneC, at: paneB, direction: .vertical, position: .after)

        // Act — remove C
        let result = layout.removing(paneId: paneC)

        // Assert — should have A | B
        #expect((result) != nil)
        #expect(result!.isSplit)
        #expect(result!.paneIds == [paneA, paneB])
    }

    @Test

    func test_remove_fromEmptyLayout_returnsNil() {
        // Arrange
        let layout = Layout()

        // Act
        let result = layout.removing(paneId: UUID())

        // Assert
        #expect((result) == nil)
    }

    // MARK: - Resize

    @Test

    func test_resize_clampsRatio() {
        // Arrange
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)

        guard case .split(let originalSplit) = layout.root else {
            Issue.record("Expected split")
            return
        }

        // Act
        let tooSmall = layout.resizing(splitId: originalSplit.id, ratio: 0.0)
        let tooLarge = layout.resizing(splitId: originalSplit.id, ratio: 1.0)

        // Assert
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

    func test_resize_updatesCorrectSplit() {
        // Arrange — A | (B / C)
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)
            .inserting(paneId: paneC, at: paneB, direction: .vertical, position: .after)

        guard case .split(let rootSplit) = layout.root,
            case .split(let nestedSplit) = rootSplit.right
        else {
            Issue.record("Expected nested split structure")
            return
        }

        // Act — resize the nested split
        let result = layout.resizing(splitId: nestedSplit.id, ratio: 0.3)

        // Assert
        guard case .split(let newRoot) = result.root else {
            Issue.record("Expected split root")
            return
        }
        #expect(abs((newRoot.ratio) - (0.5)) <= 0.001, "Root ratio should be unchanged")

        guard case .split(let newNested) = newRoot.right else {
            Issue.record("Expected nested split")
            return
        }
        #expect(abs((newNested.ratio) - (0.3)) <= 0.001)
    }

    @Test

    func test_resize_nonExistentSplitId_returnsUnchanged() {
        // Arrange
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)

        // Act
        let result = layout.resizing(splitId: UUID(), ratio: 0.3)

        // Assert
        guard case .split(let split) = result.root else {
            Issue.record("Expected split")
            return
        }
        #expect(abs((split.ratio) - (0.5)) <= 0.001, "Ratio should be unchanged")
    }

    // MARK: - Equalize

    @Test

    func test_equalize_setsAllRatiosToHalf() {
        // Arrange — A | (B / C) with non-0.5 ratios
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)
            .inserting(paneId: paneC, at: paneB, direction: .vertical, position: .after)

        guard case .split(let rootSplit) = layout.root,
            case .split(let nestedSplit) = rootSplit.right
        else {
            Issue.record("Expected structure")
            return
        }

        let resized =
            layout
            .resizing(splitId: rootSplit.id, ratio: 0.3)
            .resizing(splitId: nestedSplit.id, ratio: 0.7)

        // Act
        let equalized = resized.equalized()

        // Assert
        guard case .split(let eqRoot) = equalized.root else {
            Issue.record("Expected root split")
            return
        }
        #expect(abs((eqRoot.ratio) - (0.5)) <= 0.001)

        guard case .split(let eqNested) = eqRoot.right else {
            Issue.record("Expected nested split")
            return
        }
        #expect(abs((eqNested.ratio) - (0.5)) <= 0.001)
    }

    // MARK: - Pane IDs Ordering

    @Test

    func test_paneIds_orderedLeftToRight() {
        // Arrange — A | B
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)

        // Assert
        #expect(layout.paneIds == [paneA, paneB])
    }

    @Test

    func test_paneIds_deepTree_orderedCorrectly() {
        // Arrange — A | (B / C)
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)
            .inserting(paneId: paneC, at: paneB, direction: .vertical, position: .after)

        // Assert — A, B, C
        #expect(layout.paneIds == [paneA, paneB, paneC])
    }

    // MARK: - Navigation: neighbor

    @Test

    func test_neighbor_horizontalSplit_right() {
        // Arrange — A | B
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)

        // Act
        let neighbor = layout.neighbor(of: paneA, direction: .right)

        // Assert
        #expect(neighbor == paneB)
    }

    @Test

    func test_neighbor_horizontalSplit_left() {
        // Arrange — A | B
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)

        // Act
        let neighbor = layout.neighbor(of: paneB, direction: .left)

        // Assert
        #expect(neighbor == paneA)
    }

    @Test

    func test_neighbor_verticalSplit_down() {
        // Arrange — A / B (vertical)
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .vertical, position: .after)

        // Act
        let neighbor = layout.neighbor(of: paneA, direction: .down)

        // Assert
        #expect(neighbor == paneB)
    }

    @Test

    func test_neighbor_verticalSplit_up() {
        // Arrange — A / B (vertical)
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .vertical, position: .after)

        // Act
        let neighbor = layout.neighbor(of: paneB, direction: .up)

        // Assert
        #expect(neighbor == paneA)
    }

    @Test

    func test_neighbor_noNeighborInDirection_returnsNil() {
        // Arrange — A | B (horizontal only)
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)

        // Act — look up/down in a horizontal split
        #expect((layout.neighbor(of: paneA, direction: .up)) == nil)
        #expect((layout.neighbor(of: paneA, direction: .down)) == nil)
        #expect((layout.neighbor(of: paneA, direction: .left)) == nil)
        #expect((layout.neighbor(of: paneB, direction: .right)) == nil)
    }

    @Test

    func test_neighbor_singlePane_returnsNil() {
        // Arrange
        let paneA = UUID()
        let layout = Layout(paneId: paneA)

        // Assert
        #expect((layout.neighbor(of: paneA, direction: .right)) == nil)
        #expect((layout.neighbor(of: paneA, direction: .left)) == nil)
        #expect((layout.neighbor(of: paneA, direction: .up)) == nil)
        #expect((layout.neighbor(of: paneA, direction: .down)) == nil)
    }

    @Test

    func test_neighbor_emptyLayout_returnsNil() {
        // Arrange
        let layout = Layout()

        // Assert
        #expect((layout.neighbor(of: UUID(), direction: .right)) == nil)
    }

    // MARK: - Navigation: next/previous

    @Test

    func test_next_wrapsAround() {
        // Arrange — A | B
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)

        // Assert
        #expect(layout.next(after: paneA) == paneB)
        #expect(layout.next(after: paneB) == paneA)
    }

    @Test

    func test_previous_wrapsAround() {
        // Arrange — A | B
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)

        // Assert
        #expect(layout.previous(before: paneB) == paneA)
        #expect(layout.previous(before: paneA) == paneB)
    }

    @Test

    func test_next_singlePane_returnsSelf() {
        // Arrange
        let paneA = UUID()
        let layout = Layout(paneId: paneA)

        // Assert
        #expect(layout.next(after: paneA) == paneA)
    }

    @Test

    func test_next_nonExistent_returnsNil() {
        // Arrange
        let layout = Layout(paneId: UUID())

        // Assert
        #expect((layout.next(after: UUID())) == nil)
    }

    @Test

    func test_next_threePane_wrapsCorrectly() {
        // Arrange — A | (B / C)
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)
            .inserting(paneId: paneC, at: paneB, direction: .vertical, position: .after)

        // Assert
        #expect(layout.next(after: paneA) == paneB)
        #expect(layout.next(after: paneB) == paneC)
        #expect(layout.next(after: paneC) == paneA)
    }

    // MARK: - Codable Round-Trip

    @Test

    func test_codable_emptyLayout_roundTrips() throws {
        // Arrange
        let layout = Layout()

        // Act
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(Layout.self, from: data)

        // Assert
        #expect(decoded.isEmpty)
        #expect((decoded.root) == nil)
    }

    @Test

    func test_codable_singlePane_roundTrips() throws {
        // Arrange
        let paneId = UUID()
        let layout = Layout(paneId: paneId)

        // Act
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(Layout.self, from: data)

        // Assert
        #expect(!(decoded.isEmpty))
        #expect(!(decoded.isSplit))
        #expect(decoded.paneIds == [paneId])
    }

    @Test

    func test_codable_splitLayout_roundTrips() throws {
        // Arrange
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)

        guard case .split(let originalSplit) = layout.root else {
            Issue.record("Expected split")
            return
        }
        let resized = layout.resizing(splitId: originalSplit.id, ratio: 0.3)

        // Act
        let data = try JSONEncoder().encode(resized)
        let decoded = try JSONDecoder().decode(Layout.self, from: data)

        // Assert
        #expect(decoded.isSplit)
        #expect(decoded.paneIds == [paneA, paneB])

        guard case .split(let decodedSplit) = decoded.root else {
            Issue.record("Expected split")
            return
        }
        #expect(decodedSplit.direction == .horizontal)
        #expect(abs((decodedSplit.ratio) - (0.3)) <= 0.001)
        #expect(decodedSplit.id == originalSplit.id)
    }

    @Test

    func test_codable_deepLayout_roundTrips() throws {
        // Arrange — A | (B / C) with mixed ratios
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)
            .inserting(paneId: paneC, at: paneB, direction: .vertical, position: .after)

        guard case .split(let rootSplit) = layout.root else {
            Issue.record("Expected root split")
            return
        }
        let resized = layout.resizing(splitId: rootSplit.id, ratio: 0.4)

        // Act
        let data = try JSONEncoder().encode(resized)
        let decoded = try JSONDecoder().decode(Layout.self, from: data)

        // Assert
        #expect(decoded.paneIds == [paneA, paneB, paneC])

        guard case .split(let decodedRoot) = decoded.root else {
            Issue.record("Expected root split")
            return
        }
        #expect(decodedRoot.direction == .horizontal)
        #expect(abs((decodedRoot.ratio) - (0.4)) <= 0.001)

        guard case .split(let decodedNested) = decodedRoot.right else {
            Issue.record("Expected nested split")
            return
        }
        #expect(decodedNested.direction == .vertical)
        #expect(abs((decodedNested.ratio) - (0.5)) <= 0.001)
    }

    // MARK: - Hashable

    @Test

    func test_hashable_sameStructure_areEqual() {
        // Arrange
        let paneId = UUID()
        let layout1 = Layout(paneId: paneId)
        let layout2 = Layout(paneId: paneId)

        // Assert
        #expect(layout1 == layout2)
    }

    @Test

    func test_hashable_differentStructure_areNotEqual() {
        // Arrange
        let layout1 = Layout(paneId: UUID())
        let layout2 = Layout(paneId: UUID())

        // Assert
        #expect(layout1 != layout2)
    }

    // MARK: - Split Ratio Clamping on Init

    @Test

    func test_splitInit_clampsRatioMin() {
        // Arrange & Act
        let split = Layout.Split(
            direction: .horizontal,
            ratio: -0.5,
            left: .leaf(paneId: UUID()),
            right: .leaf(paneId: UUID())
        )

        // Assert
        #expect(abs((split.ratio) - (0.1)) <= 0.001)
    }

    @Test

    func test_splitInit_clampsRatioMax() {
        // Arrange & Act
        let split = Layout.Split(
            direction: .horizontal,
            ratio: 1.5,
            left: .leaf(paneId: UUID()),
            right: .leaf(paneId: UUID())
        )

        // Assert
        #expect(abs((split.ratio) - (0.9)) <= 0.001)
    }

    @Test

    func test_splitInit_normalRatioUnchanged() {
        // Arrange & Act
        let split = Layout.Split(
            direction: .vertical,
            ratio: 0.7,
            left: .leaf(paneId: UUID()),
            right: .leaf(paneId: UUID())
        )

        // Assert
        #expect(abs((split.ratio) - (0.7)) <= 0.001)
    }

}
