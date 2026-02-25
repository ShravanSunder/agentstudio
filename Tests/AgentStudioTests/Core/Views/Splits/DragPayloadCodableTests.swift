import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers

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

    @Test
    func test_decodeSplitDropPayload_prefersPanePayloadWhenPresent() async throws {
        // Arrange
        let panePayload = PaneDragPayload(paneId: UUID(), tabId: UUID())
        let tabPayload = TabDragPayload(tabId: UUID())
        let providers = [
            try makeProvider(
                payload: tabPayload,
                typeIdentifier: UTType.agentStudioTab.identifier
            ),
            try makeProvider(
                payload: panePayload,
                typeIdentifier: UTType.agentStudioPane.identifier
            ),
        ]

        // Act
        let decoded = await decodeSplitDropPayload(from: providers)

        // Assert
        #expect(
            decoded == SplitDropPayload(kind: .existingPane(paneId: panePayload.paneId, sourceTabId: panePayload.tabId))
        )
    }

    @Test
    func test_decodeSplitDropPayload_decodesNewTerminalPayload() async {
        // Arrange
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.agentStudioNewTab.identifier,
            visibility: .all
        ) { completion in
            completion(Data(), nil)
            return nil
        }

        // Act
        let decoded = await decodeSplitDropPayload(from: [provider])

        // Assert
        #expect(decoded == SplitDropPayload(kind: .newTerminal))
    }

    @Test
    func test_decodeSplitDropPayload_fromPasteboard_prefersPanePayloadWhenPresent() throws {
        // Arrange
        let panePayload = PaneDragPayload(paneId: UUID(), tabId: UUID())
        let tabPayload = TabDragPayload(tabId: UUID())
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setData(
            try JSONEncoder().encode(tabPayload),
            forType: NSPasteboard.PasteboardType.agentStudioTabDrop
        )
        pasteboard.setData(
            try JSONEncoder().encode(panePayload),
            forType: NSPasteboard.PasteboardType.agentStudioPaneDrop
        )

        // Act
        let decoded = decodeSplitDropPayload(from: pasteboard)

        // Assert
        #expect(
            decoded == SplitDropPayload(kind: .existingPane(paneId: panePayload.paneId, sourceTabId: panePayload.tabId))
        )
    }

    @Test
    func test_decodeSplitDropPayload_fromPasteboard_decodesInternalTabFallback() {
        // Arrange
        let tabId = UUID()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString(
            tabId.uuidString,
            forType: NSPasteboard.PasteboardType.agentStudioTabInternal
        )

        // Act
        let decoded = decodeSplitDropPayload(from: pasteboard)

        // Assert
        #expect(decoded == SplitDropPayload(kind: .existingTab(tabId: tabId)))
    }

    @Test
    func test_decodeSplitDropPayload_fromPasteboard_decodesNewTerminalPayload() {
        // Arrange
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setData(
            Data(),
            forType: NSPasteboard.PasteboardType.agentStudioNewTabDrop
        )

        // Act
        let decoded = decodeSplitDropPayload(from: pasteboard)

        // Assert
        #expect(decoded == SplitDropPayload(kind: .newTerminal))
    }

    private func makeProvider<TPayload: Encodable>(
        payload: TPayload,
        typeIdentifier: String
    ) throws -> NSItemProvider {
        let data = try JSONEncoder().encode(payload)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }
}
