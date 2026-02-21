import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class DragPayloadCodableTests {

    // MARK: - TabDragPayload

    @Test

    func test_tabDragPayload_roundTrip() throws {
        // Arrange
        let tabId = UUID()
        let original = TabDragPayload(tabId: tabId)

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TabDragPayload.self, from: data)

        // Assert
        #expect(decoded.tabId == tabId)
    }

    // MARK: - PaneDragPayload

    @Test

    func test_paneDragPayload_roundTrip() throws {
        // Arrange
        let paneId = UUID()
        let tabId = UUID()
        let original = PaneDragPayload(paneId: paneId, tabId: tabId)

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PaneDragPayload.self, from: data)

        // Assert
        #expect(decoded.paneId == paneId)
        #expect(decoded.tabId == tabId)
    }

    // MARK: - SplitDropPayload

    @Test

    func test_splitDropPayload_existingTab_roundTrip() throws {
        // Arrange
        let tabId = UUID()
        let original = SplitDropPayload(kind: .existingTab(tabId: tabId))

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SplitDropPayload.self, from: data)

        // Assert
        #expect(decoded.kind == .existingTab(tabId: tabId))
    }

    @Test

    func test_splitDropPayload_existingPane_roundTrip() throws {
        // Arrange
        let paneId = UUID()
        let sourceTabId = UUID()
        let original = SplitDropPayload(kind: .existingPane(paneId: paneId, sourceTabId: sourceTabId))

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SplitDropPayload.self, from: data)

        // Assert
        #expect(decoded.kind == .existingPane(paneId: paneId, sourceTabId: sourceTabId))
    }

    @Test

    func test_splitDropPayload_newTerminal_roundTrip() throws {
        // Arrange
        let original = SplitDropPayload(kind: .newTerminal)

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SplitDropPayload.self, from: data)

        // Assert
        #expect(decoded.kind == .newTerminal)
    }
}
