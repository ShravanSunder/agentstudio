import XCTest
@testable import AgentStudio

final class DragPayloadCodableTests: XCTestCase {

    // MARK: - TabDragPayload

    func test_tabDragPayload_roundTrip() throws {
        // Arrange
        let tabId = UUID()
        let original = TabDragPayload(tabId: tabId)

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TabDragPayload.self, from: data)

        // Assert
        XCTAssertEqual(decoded.tabId, tabId)
    }

    // MARK: - PaneDragPayload

    func test_paneDragPayload_roundTrip() throws {
        // Arrange
        let paneId = UUID()
        let tabId = UUID()
        let original = PaneDragPayload(paneId: paneId, tabId: tabId)

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PaneDragPayload.self, from: data)

        // Assert
        XCTAssertEqual(decoded.paneId, paneId)
        XCTAssertEqual(decoded.tabId, tabId)
    }

    // MARK: - SplitDropPayload

    func test_splitDropPayload_existingTab_roundTrip() throws {
        // Arrange
        let tabId = UUID()
        let original = SplitDropPayload(kind: .existingTab(tabId: tabId))

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SplitDropPayload.self, from: data)

        // Assert
        XCTAssertEqual(decoded.kind, .existingTab(tabId: tabId))
    }

    func test_splitDropPayload_existingPane_roundTrip() throws {
        // Arrange
        let paneId = UUID()
        let sourceTabId = UUID()
        let original = SplitDropPayload(kind: .existingPane(paneId: paneId, sourceTabId: sourceTabId))

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SplitDropPayload.self, from: data)

        // Assert
        XCTAssertEqual(decoded.kind, .existingPane(paneId: paneId, sourceTabId: sourceTabId))
    }

    func test_splitDropPayload_newTerminal_roundTrip() throws {
        // Arrange
        let original = SplitDropPayload(kind: .newTerminal)

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SplitDropPayload.self, from: data)

        // Assert
        XCTAssertEqual(decoded.kind, .newTerminal)
    }
}
