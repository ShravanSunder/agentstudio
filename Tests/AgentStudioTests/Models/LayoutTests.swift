import XCTest
@testable import AgentStudio

final class LayoutTests: XCTestCase {

    // MARK: - Initialization

    func test_emptyLayout_isEmpty() {
        // Arrange
        let layout = Layout()

        // Assert
        XCTAssertTrue(layout.isEmpty)
        XCTAssertFalse(layout.isSplit)
        XCTAssertTrue(layout.sessionIds.isEmpty)
        XCTAssertNil(layout.root)
    }

    func test_singleSession_properties() {
        // Arrange
        let sessionId = UUID()
        let layout = Layout(sessionId: sessionId)

        // Assert
        XCTAssertFalse(layout.isEmpty)
        XCTAssertFalse(layout.isSplit)
        XCTAssertEqual(layout.sessionIds, [sessionId])
    }

    // MARK: - Contains

    func test_contains_existingSession_returnsTrue() {
        // Arrange
        let sessionId = UUID()
        let layout = Layout(sessionId: sessionId)

        // Assert
        XCTAssertTrue(layout.contains(sessionId))
    }

    func test_contains_nonExistent_returnsFalse() {
        // Arrange
        let layout = Layout(sessionId: UUID())

        // Assert
        XCTAssertFalse(layout.contains(UUID()))
    }

    func test_contains_emptyLayout_returnsFalse() {
        // Arrange
        let layout = Layout()

        // Assert
        XCTAssertFalse(layout.contains(UUID()))
    }

    // MARK: - Insert

    func test_insert_after_createsSplit() {
        // Arrange
        let sessionA = UUID()
        let sessionB = UUID()
        let layout = Layout(sessionId: sessionA)

        // Act
        let result = layout.inserting(
            sessionId: sessionB, at: sessionA,
            direction: .horizontal, position: .after
        )

        // Assert
        XCTAssertTrue(result.isSplit)
        XCTAssertEqual(result.sessionIds.count, 2)
        XCTAssertEqual(result.sessionIds[0], sessionA)
        XCTAssertEqual(result.sessionIds[1], sessionB)

        guard case .split(let split) = result.root else {
            XCTFail("Expected split node")
            return
        }
        XCTAssertEqual(split.direction, .horizontal)
        XCTAssertEqual(split.ratio, 0.5, accuracy: 0.001)
    }

    func test_insert_before_createsSplit() {
        // Arrange
        let sessionA = UUID()
        let sessionB = UUID()
        let layout = Layout(sessionId: sessionA)

        // Act
        let result = layout.inserting(
            sessionId: sessionB, at: sessionA,
            direction: .horizontal, position: .before
        )

        // Assert
        XCTAssertEqual(result.sessionIds.count, 2)
        XCTAssertEqual(result.sessionIds[0], sessionB)
        XCTAssertEqual(result.sessionIds[1], sessionA)
    }

    func test_insert_vertical_after() {
        // Arrange
        let sessionA = UUID()
        let sessionB = UUID()
        let layout = Layout(sessionId: sessionA)

        // Act
        let result = layout.inserting(
            sessionId: sessionB, at: sessionA,
            direction: .vertical, position: .after
        )

        // Assert
        guard case .split(let split) = result.root else {
            XCTFail("Expected split node")
            return
        }
        XCTAssertEqual(split.direction, .vertical)
        XCTAssertEqual(result.sessionIds[0], sessionA)
        XCTAssertEqual(result.sessionIds[1], sessionB)
    }

    func test_insert_vertical_before() {
        // Arrange
        let sessionA = UUID()
        let sessionB = UUID()
        let layout = Layout(sessionId: sessionA)

        // Act
        let result = layout.inserting(
            sessionId: sessionB, at: sessionA,
            direction: .vertical, position: .before
        )

        // Assert
        XCTAssertEqual(result.sessionIds[0], sessionB)
        XCTAssertEqual(result.sessionIds[1], sessionA)
    }

    func test_insert_targetNotFound_returnsUnchanged() {
        // Arrange
        let sessionA = UUID()
        let layout = Layout(sessionId: sessionA)

        // Act
        let result = layout.inserting(
            sessionId: UUID(), at: UUID(),
            direction: .horizontal, position: .after
        )

        // Assert
        XCTAssertEqual(result.sessionIds, [sessionA])
    }

    func test_insert_nested_createsDeepTree() {
        // Arrange — A | B
        let sessionA = UUID()
        let sessionB = UUID()
        let sessionC = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)

        // Act — insert C below B
        let result = layout.inserting(
            sessionId: sessionC, at: sessionB,
            direction: .vertical, position: .after
        )

        // Assert — should have 3 sessions: A, B, C
        XCTAssertEqual(result.sessionIds, [sessionA, sessionB, sessionC])

        guard case .split(let rootSplit) = result.root else {
            XCTFail("Expected split root")
            return
        }
        XCTAssertEqual(rootSplit.direction, .horizontal)

        guard case .split(let rightSplit) = rootSplit.right else {
            XCTFail("Expected nested split")
            return
        }
        XCTAssertEqual(rightSplit.direction, .vertical)
    }

    func test_insert_intoEmptyLayout_returnsUnchanged() {
        // Arrange
        let layout = Layout()

        // Act
        let result = layout.inserting(
            sessionId: UUID(), at: UUID(),
            direction: .horizontal, position: .after
        )

        // Assert
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Remove

    func test_remove_singleSession_returnsNil() {
        // Arrange
        let sessionId = UUID()
        let layout = Layout(sessionId: sessionId)

        // Act
        let result = layout.removing(sessionId: sessionId)

        // Assert
        XCTAssertNil(result)
    }

    func test_remove_fromSplit_collapsesToLeaf() {
        // Arrange — A | B
        let sessionA = UUID()
        let sessionB = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)

        // Act — remove A
        let result = layout.removing(sessionId: sessionA)

        // Assert — should collapse to just B
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isSplit)
        XCTAssertEqual(result!.sessionIds, [sessionB])
    }

    func test_remove_nonExistent_returnsUnchanged() {
        // Arrange
        let sessionA = UUID()
        let layout = Layout(sessionId: sessionA)

        // Act
        let result = layout.removing(sessionId: UUID())

        // Assert
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.sessionIds, [sessionA])
    }

    func test_remove_fromDeepTree_preservesOtherBranches() {
        // Arrange — A | (B / C)
        let sessionA = UUID()
        let sessionB = UUID()
        let sessionC = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)
            .inserting(sessionId: sessionC, at: sessionB, direction: .vertical, position: .after)

        // Act — remove C
        let result = layout.removing(sessionId: sessionC)

        // Assert — should have A | B
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isSplit)
        XCTAssertEqual(result!.sessionIds, [sessionA, sessionB])
    }

    func test_remove_fromEmptyLayout_returnsNil() {
        // Arrange
        let layout = Layout()

        // Act
        let result = layout.removing(sessionId: UUID())

        // Assert
        XCTAssertNil(result)
    }

    // MARK: - Resize

    func test_resize_clampsRatio() {
        // Arrange
        let sessionA = UUID()
        let sessionB = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)

        guard case .split(let originalSplit) = layout.root else {
            XCTFail("Expected split")
            return
        }

        // Act
        let tooSmall = layout.resizing(splitId: originalSplit.id, ratio: 0.0)
        let tooLarge = layout.resizing(splitId: originalSplit.id, ratio: 1.0)

        // Assert
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

    func test_resize_updatesCorrectSplit() {
        // Arrange — A | (B / C)
        let sessionA = UUID()
        let sessionB = UUID()
        let sessionC = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)
            .inserting(sessionId: sessionC, at: sessionB, direction: .vertical, position: .after)

        guard case .split(let rootSplit) = layout.root,
              case .split(let nestedSplit) = rootSplit.right else {
            XCTFail("Expected nested split structure")
            return
        }

        // Act — resize the nested split
        let result = layout.resizing(splitId: nestedSplit.id, ratio: 0.3)

        // Assert
        guard case .split(let newRoot) = result.root else {
            XCTFail("Expected split root")
            return
        }
        XCTAssertEqual(newRoot.ratio, 0.5, accuracy: 0.001, "Root ratio should be unchanged")

        guard case .split(let newNested) = newRoot.right else {
            XCTFail("Expected nested split")
            return
        }
        XCTAssertEqual(newNested.ratio, 0.3, accuracy: 0.001)
    }

    func test_resize_nonExistentSplitId_returnsUnchanged() {
        // Arrange
        let sessionA = UUID()
        let sessionB = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)

        // Act
        let result = layout.resizing(splitId: UUID(), ratio: 0.3)

        // Assert
        guard case .split(let split) = result.root else {
            XCTFail("Expected split")
            return
        }
        XCTAssertEqual(split.ratio, 0.5, accuracy: 0.001, "Ratio should be unchanged")
    }

    // MARK: - Equalize

    func test_equalize_setsAllRatiosToHalf() {
        // Arrange — A | (B / C) with non-0.5 ratios
        let sessionA = UUID()
        let sessionB = UUID()
        let sessionC = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)
            .inserting(sessionId: sessionC, at: sessionB, direction: .vertical, position: .after)

        guard case .split(let rootSplit) = layout.root,
              case .split(let nestedSplit) = rootSplit.right else {
            XCTFail("Expected structure")
            return
        }

        let resized = layout
            .resizing(splitId: rootSplit.id, ratio: 0.3)
            .resizing(splitId: nestedSplit.id, ratio: 0.7)

        // Act
        let equalized = resized.equalized()

        // Assert
        guard case .split(let eqRoot) = equalized.root else {
            XCTFail("Expected root split")
            return
        }
        XCTAssertEqual(eqRoot.ratio, 0.5, accuracy: 0.001)

        guard case .split(let eqNested) = eqRoot.right else {
            XCTFail("Expected nested split")
            return
        }
        XCTAssertEqual(eqNested.ratio, 0.5, accuracy: 0.001)
    }

    // MARK: - Session IDs Ordering

    func test_sessionIds_orderedLeftToRight() {
        // Arrange — A | B
        let sessionA = UUID()
        let sessionB = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)

        // Assert
        XCTAssertEqual(layout.sessionIds, [sessionA, sessionB])
    }

    func test_sessionIds_deepTree_orderedCorrectly() {
        // Arrange — A | (B / C)
        let sessionA = UUID()
        let sessionB = UUID()
        let sessionC = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)
            .inserting(sessionId: sessionC, at: sessionB, direction: .vertical, position: .after)

        // Assert — A, B, C
        XCTAssertEqual(layout.sessionIds, [sessionA, sessionB, sessionC])
    }

    // MARK: - Navigation: neighbor

    func test_neighbor_horizontalSplit_right() {
        // Arrange — A | B
        let sessionA = UUID()
        let sessionB = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)

        // Act
        let neighbor = layout.neighbor(of: sessionA, direction: .right)

        // Assert
        XCTAssertEqual(neighbor, sessionB)
    }

    func test_neighbor_horizontalSplit_left() {
        // Arrange — A | B
        let sessionA = UUID()
        let sessionB = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)

        // Act
        let neighbor = layout.neighbor(of: sessionB, direction: .left)

        // Assert
        XCTAssertEqual(neighbor, sessionA)
    }

    func test_neighbor_verticalSplit_down() {
        // Arrange — A / B (vertical)
        let sessionA = UUID()
        let sessionB = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .vertical, position: .after)

        // Act
        let neighbor = layout.neighbor(of: sessionA, direction: .down)

        // Assert
        XCTAssertEqual(neighbor, sessionB)
    }

    func test_neighbor_verticalSplit_up() {
        // Arrange — A / B (vertical)
        let sessionA = UUID()
        let sessionB = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .vertical, position: .after)

        // Act
        let neighbor = layout.neighbor(of: sessionB, direction: .up)

        // Assert
        XCTAssertEqual(neighbor, sessionA)
    }

    func test_neighbor_noNeighborInDirection_returnsNil() {
        // Arrange — A | B (horizontal only)
        let sessionA = UUID()
        let sessionB = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)

        // Act — look up/down in a horizontal split
        XCTAssertNil(layout.neighbor(of: sessionA, direction: .up))
        XCTAssertNil(layout.neighbor(of: sessionA, direction: .down))
        XCTAssertNil(layout.neighbor(of: sessionA, direction: .left))
        XCTAssertNil(layout.neighbor(of: sessionB, direction: .right))
    }

    func test_neighbor_singleSession_returnsNil() {
        // Arrange
        let sessionA = UUID()
        let layout = Layout(sessionId: sessionA)

        // Assert
        XCTAssertNil(layout.neighbor(of: sessionA, direction: .right))
        XCTAssertNil(layout.neighbor(of: sessionA, direction: .left))
        XCTAssertNil(layout.neighbor(of: sessionA, direction: .up))
        XCTAssertNil(layout.neighbor(of: sessionA, direction: .down))
    }

    func test_neighbor_emptyLayout_returnsNil() {
        // Arrange
        let layout = Layout()

        // Assert
        XCTAssertNil(layout.neighbor(of: UUID(), direction: .right))
    }

    // MARK: - Navigation: next/previous

    func test_next_wrapsAround() {
        // Arrange — A | B
        let sessionA = UUID()
        let sessionB = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)

        // Assert
        XCTAssertEqual(layout.next(after: sessionA), sessionB)
        XCTAssertEqual(layout.next(after: sessionB), sessionA)
    }

    func test_previous_wrapsAround() {
        // Arrange — A | B
        let sessionA = UUID()
        let sessionB = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)

        // Assert
        XCTAssertEqual(layout.previous(before: sessionB), sessionA)
        XCTAssertEqual(layout.previous(before: sessionA), sessionB)
    }

    func test_next_singleSession_returnsSelf() {
        // Arrange
        let sessionA = UUID()
        let layout = Layout(sessionId: sessionA)

        // Assert
        XCTAssertEqual(layout.next(after: sessionA), sessionA)
    }

    func test_next_nonExistent_returnsNil() {
        // Arrange
        let layout = Layout(sessionId: UUID())

        // Assert
        XCTAssertNil(layout.next(after: UUID()))
    }

    func test_next_threeSession_wrapsCorrectly() {
        // Arrange — A | (B / C)
        let sessionA = UUID()
        let sessionB = UUID()
        let sessionC = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)
            .inserting(sessionId: sessionC, at: sessionB, direction: .vertical, position: .after)

        // Assert
        XCTAssertEqual(layout.next(after: sessionA), sessionB)
        XCTAssertEqual(layout.next(after: sessionB), sessionC)
        XCTAssertEqual(layout.next(after: sessionC), sessionA)
    }

    // MARK: - Codable Round-Trip

    func test_codable_emptyLayout_roundTrips() throws {
        // Arrange
        let layout = Layout()

        // Act
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(Layout.self, from: data)

        // Assert
        XCTAssertTrue(decoded.isEmpty)
        XCTAssertNil(decoded.root)
    }

    func test_codable_singleSession_roundTrips() throws {
        // Arrange
        let sessionId = UUID()
        let layout = Layout(sessionId: sessionId)

        // Act
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(Layout.self, from: data)

        // Assert
        XCTAssertFalse(decoded.isEmpty)
        XCTAssertFalse(decoded.isSplit)
        XCTAssertEqual(decoded.sessionIds, [sessionId])
    }

    func test_codable_splitLayout_roundTrips() throws {
        // Arrange
        let sessionA = UUID()
        let sessionB = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)

        guard case .split(let originalSplit) = layout.root else {
            XCTFail("Expected split")
            return
        }
        let resized = layout.resizing(splitId: originalSplit.id, ratio: 0.3)

        // Act
        let data = try JSONEncoder().encode(resized)
        let decoded = try JSONDecoder().decode(Layout.self, from: data)

        // Assert
        XCTAssertTrue(decoded.isSplit)
        XCTAssertEqual(decoded.sessionIds, [sessionA, sessionB])

        guard case .split(let decodedSplit) = decoded.root else {
            XCTFail("Expected split")
            return
        }
        XCTAssertEqual(decodedSplit.direction, .horizontal)
        XCTAssertEqual(decodedSplit.ratio, 0.3, accuracy: 0.001)
        XCTAssertEqual(decodedSplit.id, originalSplit.id)
    }

    func test_codable_deepLayout_roundTrips() throws {
        // Arrange — A | (B / C) with mixed ratios
        let sessionA = UUID()
        let sessionB = UUID()
        let sessionC = UUID()
        let layout = Layout(sessionId: sessionA)
            .inserting(sessionId: sessionB, at: sessionA, direction: .horizontal, position: .after)
            .inserting(sessionId: sessionC, at: sessionB, direction: .vertical, position: .after)

        guard case .split(let rootSplit) = layout.root else {
            XCTFail("Expected root split")
            return
        }
        let resized = layout.resizing(splitId: rootSplit.id, ratio: 0.4)

        // Act
        let data = try JSONEncoder().encode(resized)
        let decoded = try JSONDecoder().decode(Layout.self, from: data)

        // Assert
        XCTAssertEqual(decoded.sessionIds, [sessionA, sessionB, sessionC])

        guard case .split(let decodedRoot) = decoded.root else {
            XCTFail("Expected root split")
            return
        }
        XCTAssertEqual(decodedRoot.direction, .horizontal)
        XCTAssertEqual(decodedRoot.ratio, 0.4, accuracy: 0.001)

        guard case .split(let decodedNested) = decodedRoot.right else {
            XCTFail("Expected nested split")
            return
        }
        XCTAssertEqual(decodedNested.direction, .vertical)
        XCTAssertEqual(decodedNested.ratio, 0.5, accuracy: 0.001)
    }

    func test_codable_wrongVersion_throws() throws {
        // Arrange — manually craft JSON with wrong version
        let json = """
        {"version": 99, "root": null}
        """
        let data = json.data(using: .utf8)!

        // Act & Assert
        XCTAssertThrowsError(try JSONDecoder().decode(Layout.self, from: data))
    }

    // MARK: - Hashable

    func test_hashable_sameStructure_areEqual() {
        // Arrange
        let sessionId = UUID()
        let layout1 = Layout(sessionId: sessionId)
        let layout2 = Layout(sessionId: sessionId)

        // Assert
        XCTAssertEqual(layout1, layout2)
    }

    func test_hashable_differentStructure_areNotEqual() {
        // Arrange
        let layout1 = Layout(sessionId: UUID())
        let layout2 = Layout(sessionId: UUID())

        // Assert
        XCTAssertNotEqual(layout1, layout2)
    }

    // MARK: - Split Ratio Clamping on Init

    func test_splitInit_clampsRatioMin() {
        // Arrange & Act
        let split = Layout.Split(
            direction: .horizontal,
            ratio: -0.5,
            left: .leaf(sessionId: UUID()),
            right: .leaf(sessionId: UUID())
        )

        // Assert
        XCTAssertEqual(split.ratio, 0.1, accuracy: 0.001)
    }

    func test_splitInit_clampsRatioMax() {
        // Arrange & Act
        let split = Layout.Split(
            direction: .horizontal,
            ratio: 1.5,
            left: .leaf(sessionId: UUID()),
            right: .leaf(sessionId: UUID())
        )

        // Assert
        XCTAssertEqual(split.ratio, 0.9, accuracy: 0.001)
    }

    func test_splitInit_normalRatioUnchanged() {
        // Arrange & Act
        let split = Layout.Split(
            direction: .vertical,
            ratio: 0.7,
            left: .leaf(sessionId: UUID()),
            right: .leaf(sessionId: UUID())
        )

        // Assert
        XCTAssertEqual(split.ratio, 0.7, accuracy: 0.001)
    }
}
