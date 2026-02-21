import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

/// Temporary smoke tests for tab/split orchestration types.
/// These test the data flow types, NOT the AppKit view controllers.
/// TODO: Remove when proper integration tests are added.
@Suite(.serialized)
final class TabSmokeTests {

    // MARK: - SplitDropPayload Equatable

    @Test

    func test_splitDropPayload_existingTab_equatable() {
        // Arrange
        let tabId = UUID()
        let p1 = SplitDropPayload(kind: .existingTab(tabId: tabId))
        let p2 = SplitDropPayload(kind: .existingTab(tabId: tabId))

        // Assert
        #expect(p1 == p2)
    }

    @Test

    func test_splitDropPayload_differentTabIds_notEqual() {
        // Arrange
        let p1 = SplitDropPayload(kind: .existingTab(tabId: UUID()))
        let p2 = SplitDropPayload(kind: .existingTab(tabId: UUID()))

        // Assert
        #expect(p1 != p2)
    }

    @Test

    func test_splitDropPayload_newTerminal_equatable() {
        // Arrange
        let p1 = SplitDropPayload(kind: .newTerminal)
        let p2 = SplitDropPayload(kind: .newTerminal)

        // Assert
        #expect(p1 == p2)
    }

    // MARK: - SplitDropPayload Codable

    @Test

    func test_splitDropPayload_codable_roundTrip() throws {
        // Arrange
        let original = SplitDropPayload(kind: .newTerminal)

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SplitDropPayload.self, from: data)

        // Assert
        #expect(decoded == original)
    }

    // MARK: - DropZone → SplitTree Integration

    /// Maps DropZone to TestSplitTree.NewDirection (bridging the generic type boundary)
    private func testDirection(for zone: DropZone) -> TestSplitTree.NewDirection {
        switch zone {
        case .left: return .left
        case .right: return .right
        }
    }

    @Test

    func test_dropZone_left_integratesWithSplitTree() throws {
        // Arrange
        let existing = MockTerminalView(name: "existing")
        let newView = MockTerminalView(name: "new")
        let tree = TestSplitTree(view: existing)

        // Act
        let result = try tree.inserting(view: newView, at: existing, direction: testDirection(for: .left))

        // Assert — new view should be on the left
        #expect(result.allViews[0] === newView)
        #expect(result.allViews[1] === existing)
    }

    @Test

    func test_dropZone_allCases_produceSplitTreeInsertions() throws {
        // Assert — each zone produces a valid 2-pane split
        for zone in DropZone.allCases {
            // Arrange
            let existing = MockTerminalView(name: "existing")
            let newView = MockTerminalView(name: "new")
            let tree = TestSplitTree(view: existing)

            // Act
            let result = try tree.inserting(view: newView, at: existing, direction: testDirection(for: zone))

            // Assert
            #expect(result.allViews.count == 2, "DropZone.\(zone) should produce a 2-pane split")
        }
    }

}
