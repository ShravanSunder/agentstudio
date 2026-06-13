import Foundation
import Testing

@testable import AgentStudio

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

    @Test("pane metadata note round-trips through persistence encoding")
    func paneMetadataNoteRoundTripsThroughPersistenceEncoding() throws {
        let original = PaneMetadata(
            title: "Terminal",
            note: "  Keep an eye on deploy logs  "
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PaneMetadata.self, from: data)

        #expect(decoded == original)
        #expect(decoded.note == "Keep an eye on deploy logs")
    }
}
