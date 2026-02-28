import Foundation
import Testing

@testable import AgentStudio

@Suite
struct PaneIdTests {

    // MARK: - Creation

    @Test
    func defaultInitCreatesV7UUID() {
        // Act
        let paneId = PaneId()

        // Assert
        #expect(paneId.isV7, "Default PaneId should use UUID v7")
    }

    @Test
    func uuidInitWrapsExistingUUID() {
        // Arrange
        let existing = UUIDv7.generate(milliseconds: 1_700_000_000_000)

        // Act
        let paneId = PaneId(uuid: existing)

        // Assert
        #expect(paneId.uuid == existing)
        #expect(paneId.isV7, "Wrapped UUID should remain v7 in canonical flows")
    }

    // MARK: - hexPrefix

    @Test
    func hexPrefixReturns16LowercaseHexChars() {
        // Arrange
        let paneId = PaneId(uuid: UUID(uuidString: "01890f10-1234-7abc-8def-0123456789ab")!)

        // Act
        let prefix = paneId.hexPrefix

        // Assert
        #expect(prefix == "01890f1012347abc")
        #expect(prefix.count == 16)
    }

    @Test
    func hexPrefixIsAlwaysLowercase() {
        // Act — generate several PaneIds
        for _ in 0..<20 {
            let paneId = PaneId()
            let prefix = paneId.hexPrefix
            #expect(prefix == prefix.lowercased(), "hexPrefix must be lowercase: \(prefix)")
            #expect(prefix.count == 16)
        }
    }

    @Test
    func hexPrefixMatchesDocumentedDerivation() {
        // The documented derivation from session_lifecycle.md:
        // pane16 = first16hex(lowercase(removeHyphens(paneId.uuidString)))
        let uuid = UUID(uuidString: "01890F10-1234-7ABC-8DEF-0123456789AB")!
        let paneId = PaneId(uuid: uuid)

        // Manual derivation
        let expected = String(
            uuid.uuidString
                .replacingOccurrences(of: "-", with: "")
                .prefix(16)
        ).lowercased()

        #expect(paneId.hexPrefix == expected)
        #expect(paneId.hexPrefix == "01890f1012347abc")
    }

    // MARK: - fullHex

    @Test
    func fullHexReturns32LowercaseHexChars() {
        // Arrange
        let paneId = PaneId(uuid: UUID(uuidString: "01890f10-1234-7abc-8def-0123456789ab")!)

        // Act & Assert
        let expected = "01890f1012347abc8def0123456789ab"
        #expect(paneId.fullHex == expected)
        #expect(paneId.fullHex.count == 32)
    }

    // MARK: - Codable

    @Test
    func codableRoundTrip() throws {
        // Arrange
        let original = PaneId()

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PaneId.self, from: data)

        // Assert
        #expect(decoded == original)
        #expect(decoded.uuid == original.uuid)
    }

    @Test
    func codableDecodesFromBareUUIDString() throws {
        // Arrange
        let canonicalUUID = UUID(uuidString: "01890f10-1234-7abc-8def-0123456789ab")!
        let canonicalData = try JSONEncoder().encode(canonicalUUID)

        // Act — decode as PaneId
        let paneId = try JSONDecoder().decode(PaneId.self, from: canonicalData)

        // Assert
        #expect(paneId.uuid == canonicalUUID)
        #expect(paneId.isV7)
    }

    @Test
    func codableRejectsNonV7UUIDString() throws {
        let v4UUID = UUID(uuidString: "AABBCCDD-1122-3344-5566-778899001122")!
        let v4Data = try JSONEncoder().encode(v4UUID)

        #expect(throws: Error.self) {
            try JSONDecoder().decode(PaneId.self, from: v4Data)
        }
    }

    @Test
    func codableEncodesToBareUUIDString() throws {
        // Arrange
        let uuid = UUID(uuidString: "01890f10-1234-7abc-8def-0123456789ab")!
        let paneId = PaneId(uuid: uuid)

        // Act
        let paneIdData = try JSONEncoder().encode(paneId)
        let uuidData = try JSONEncoder().encode(uuid)

        // Assert — PaneId and UUID produce identical JSON
        #expect(paneIdData == uuidData)
    }

    @Test
    func codableWorksInDictionary() throws {
        // Arrange — simulate WorkspaceStore's [PaneId: SomeValue] pattern
        let id1 = PaneId()
        let id2 = PaneId()
        let dict: [PaneId: String] = [id1: "pane-a", id2: "pane-b"]

        // Act — this verifies PaneId works as a Codable dictionary key
        // (requires CodingKeyRepresentable or string-keyed encoding)
        let data = try JSONEncoder().encode(dict)
        let decoded = try JSONDecoder().decode([PaneId: String].self, from: data)

        // Assert
        #expect(decoded[id1] == "pane-a")
        #expect(decoded[id2] == "pane-b")
    }

    // MARK: - Hashable & Equatable

    @Test
    func equalityBasedOnUUID() {
        // Arrange
        let uuid = UUIDv7.generate(milliseconds: 1_700_000_000_000)
        let a = PaneId(uuid: uuid)
        let b = PaneId(uuid: uuid)

        // Assert
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test
    func inequalityForDifferentUUIDs() {
        let a = PaneId()
        let b = PaneId()
        #expect(a != b)
    }

    @Test
    func worksAsSetElement() {
        // Arrange
        let id = PaneId()
        var set: Set<PaneId> = [id, id, id]

        // Assert
        #expect(set.count == 1)
        #expect(set.contains(id))

        set.insert(PaneId())
        #expect(set.count == 2)
    }

    @Test
    func worksAsDictionaryKey() {
        // Arrange
        let id = PaneId()
        var dict: [PaneId: String] = [:]

        // Act
        dict[id] = "test"

        // Assert
        #expect(dict[id] == "test")
    }

    // MARK: - Comparable (Temporal Ordering)

    @Test
    func v7PaneIdsCompareByCreationTime() {
        // Arrange — create with increasing timestamps
        let earlier = PaneId(uuid: UUIDv7.generate(milliseconds: 1_700_000_000_000))
        let later = PaneId(uuid: UUIDv7.generate(milliseconds: 1_700_000_001_000))

        // Assert
        #expect(earlier < later)
        #expect(!(later < earlier))
    }

    // MARK: - String Representations

    @Test
    func descriptionIsUUIDString() {
        let uuid = UUID(uuidString: "01890f10-1234-7abc-8def-0123456789ab")!
        let paneId = PaneId(uuid: uuid)
        #expect(paneId.description == uuid.uuidString)
        #expect(paneId.uuidString == uuid.uuidString)
    }

    @Test
    func debugDescriptionIncludesVersion() {
        let v7 = PaneId()
        #expect(v7.debugDescription.contains("v7=true"))
    }

    // MARK: - createdAt

    @Test
    func createdAtReturnsDateForV7() {
        // Arrange
        let before = Date()
        let paneId = PaneId()

        // Assert
        guard let createdAt = paneId.createdAt else {
            Issue.record("v7 PaneId should have createdAt")
            return
        }
        #expect(createdAt >= before.addingTimeInterval(-0.1))
        #expect(createdAt <= Date().addingTimeInterval(0.1))
    }

}
