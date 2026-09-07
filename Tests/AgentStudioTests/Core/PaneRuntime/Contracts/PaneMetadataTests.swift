import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@Suite
struct PaneMetadataTests {
    @Test("pane note trims whitespace and stores nil for blank notes")
    func paneNoteNormalizesBlankValues() {
        var metadata = PaneMetadata(
            title: "Terminal"
        )

        metadata.updateNote("  Debug checkout  ")
        #expect(metadata.note == "Debug checkout")

        metadata.updateNote("   ")
        #expect(metadata.note == nil)
    }

    @Test("pane metadata decodes persisted values without a note")
    func paneMetadataDecodesWithoutNote() throws {
        let original = PaneMetadata(
            title: "Terminal"
        )
        var payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        payload.removeValue(forKey: "note")
        let data = try JSONSerialization.data(withJSONObject: payload)

        let metadata = try JSONDecoder().decode(PaneMetadata.self, from: data)

        #expect(metadata.note == nil)
    }

    @Test("pane metadata decodes persisted values without a pin as unpinned")
    func paneMetadataDecodesWithoutPinAsUnpinned() throws {
        let original = PaneMetadata(title: "Terminal", isPinned: true)
        var payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        payload.removeValue(forKey: "isPinned")
        let data = try JSONSerialization.data(withJSONObject: payload)

        let metadata = try JSONDecoder().decode(PaneMetadata.self, from: data)

        #expect(!metadata.isPinned)
    }

    @Test("pane metadata construction and persistence preserve caller-supplied note exactly")
    func paneMetadataNoteRoundTripsExactlyThroughPersistenceEncoding() throws {
        let original = PaneMetadata(
            title: "Terminal",
            note: "  Keep an eye on deploy logs  "
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PaneMetadata.self, from: data)

        #expect(decoded == original)
        #expect(decoded.note == "  Keep an eye on deploy logs  ")
    }

    @Test("pane metadata pin round trips independently from repository facets")
    func paneMetadataPinRoundTripsIndependentlyFromRepositoryFacets() throws {
        let original = PaneMetadata(
            title: "Pinned terminal",
            facets: .init(repoId: UUIDv7.generate(), worktreeId: UUIDv7.generate()),
            isPinned: true
        )

        let decoded = try JSONDecoder().decode(PaneMetadata.self, from: JSONEncoder().encode(original))

        #expect(decoded == original)
        #expect(decoded.isPinned)
    }
}
