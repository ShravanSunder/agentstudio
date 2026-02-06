import XCTest
import AppKit
import CoreGraphics
@testable import AgentStudio

/// Temporary smoke tests for tab/split orchestration types.
/// These test the data flow types, NOT the AppKit view controllers.
/// TODO: Remove when proper integration tests are added.
final class TabSmokeTests: XCTestCase {

    // MARK: - SplitDropPayload Equatable

    func test_splitDropPayload_existingTab_equatable() {
        // Arrange
        let tabId = UUID()
        let wtId = UUID()
        let pId = UUID()
        let p1 = SplitDropPayload(kind: .existingTab(tabId: tabId, worktreeId: wtId, projectId: pId, title: "Tab"))
        let p2 = SplitDropPayload(kind: .existingTab(tabId: tabId, worktreeId: wtId, projectId: pId, title: "Tab"))

        // Assert
        XCTAssertEqual(p1, p2)
    }

    func test_splitDropPayload_differentTabIds_notEqual() {
        // Arrange
        let p1 = SplitDropPayload(kind: .existingTab(tabId: UUID(), worktreeId: UUID(), projectId: UUID(), title: "A"))
        let p2 = SplitDropPayload(kind: .existingTab(tabId: UUID(), worktreeId: UUID(), projectId: UUID(), title: "B"))

        // Assert
        XCTAssertNotEqual(p1, p2)
    }

    func test_splitDropPayload_newTerminal_equatable() {
        // Arrange
        let p1 = SplitDropPayload(kind: .newTerminal)
        let p2 = SplitDropPayload(kind: .newTerminal)

        // Assert
        XCTAssertEqual(p1, p2)
    }

    // MARK: - SplitDropPayload Codable

    func test_splitDropPayload_codable_roundTrip() throws {
        // Arrange
        let original = SplitDropPayload(kind: .newTerminal)

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SplitDropPayload.self, from: data)

        // Assert
        XCTAssertEqual(decoded, original)
    }

    // MARK: - DropZone → SplitTree Integration

    /// Maps DropZone to TestSplitTree.NewDirection (bridging the generic type boundary)
    private func testDirection(for zone: DropZone) -> TestSplitTree.NewDirection {
        switch zone {
        case .left: return .left
        case .right: return .right
        case .top: return .up
        case .bottom: return .down
        }
    }

    func test_dropZone_left_integratesWithSplitTree() throws {
        // Arrange
        let existing = MockTerminalView(name: "existing")
        let newView = MockTerminalView(name: "new")
        let tree = TestSplitTree(view: existing)

        // Act
        let result = try tree.inserting(view: newView, at: existing, direction: testDirection(for: .left))

        // Assert — new view should be on the left
        XCTAssertTrue(result.allViews[0] === newView)
        XCTAssertTrue(result.allViews[1] === existing)
    }

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
            XCTAssertEqual(result.allViews.count, 2, "DropZone.\(zone) should produce a 2-pane split")
        }
    }

    // MARK: - Tab Ordering

    func test_openTab_sorting_byOrder() {
        // Arrange
        let tab1 = makeOpenTab(order: 2)
        let tab2 = makeOpenTab(order: 0)
        let tab3 = makeOpenTab(order: 1)

        // Act
        let sorted = [tab1, tab2, tab3].sorted { $0.order < $1.order }

        // Assert
        XCTAssertEqual(sorted[0].order, 0)
        XCTAssertEqual(sorted[1].order, 1)
        XCTAssertEqual(sorted[2].order, 2)
    }
}
