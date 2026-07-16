import Foundation
import Testing

@testable import AgentStudio

@Suite("ZmxSessionIDTests")
struct ZmxSessionIDTests {
    @Test("generation produces UUIDv7 text")
    func generationProducesUUIDv7Text() throws {
        let generatedSessionID = ZmxSessionID.generateUUIDv7()

        let generatedUUID = try #require(UUID(uuidString: generatedSessionID.rawValue))
        #expect(UUIDv7.isV7(generatedUUID))
        #expect(generatedSessionID.rawValue == generatedUUID.uuidString)
    }

    @Test("restoration preserves legacy compound identity verbatim")
    func restorationPreservesLegacyCompoundIdentityVerbatim() throws {
        let storedText = "as-a1b2c3d4e5f6a7b8-00112233aabbccdd-5566778899001122"

        let restoredSessionID = try #require(ZmxSessionID(restoring: storedText))

        #expect(restoredSessionID.rawValue == storedText)
    }

    @Test("restoration preserves older UUID versions verbatim")
    func restorationPreservesOlderUUIDVersionsVerbatim() throws {
        let uuidV4Text = "550E8400-E29B-41D4-A716-446655440000"

        let restoredSessionID = try #require(ZmxSessionID(restoring: uuidV4Text))

        #expect(restoredSessionID.rawValue == uuidV4Text)
    }

    @Test("empty and blank persisted identities are rejected")
    func emptyAndBlankPersistedIdentitiesAreRejected() {
        #expect(ZmxSessionID(restoring: "") == nil)
        #expect(ZmxSessionID(restoring: "   \n\t") == nil)
    }

    @Test("Codable round trip preserves exact opaque text")
    func codableRoundTripPreservesExactOpaqueText() throws {
        let storedText = "as-d--bc219f0a5b7c8d9e--a1234f00b16e1aa2"
        let originalSessionID = try #require(ZmxSessionID(restoring: storedText))

        let encodedSessionID = try JSONEncoder().encode(originalSessionID)
        let decodedSessionID = try JSONDecoder().decode(
            ZmxSessionID.self,
            from: encodedSessionID
        )

        #expect(decodedSessionID == originalSessionID)
        #expect(decodedSessionID.rawValue == storedText)
    }

    @Test("Codable rejects empty and null persisted identities")
    func codableRejectsEmptyAndNullPersistedIdentities() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ZmxSessionID.self, from: Data("\"\"".utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ZmxSessionID.self, from: Data("null".utf8))
        }
    }

    @Test("terminal state exposes a nonoptional strong identity")
    func terminalStateExposesNonoptionalStrongIdentity() {
        let generatedSessionID = ZmxSessionID.generateUUIDv7()

        let terminalState = TerminalState(
            provider: .ghostty,
            lifetime: .temporary,
            zmxSessionID: generatedSessionID
        )
        let stronglyTypedSessionID: ZmxSessionID = terminalState.zmxSessionID

        #expect(stronglyTypedSessionID == generatedSessionID)
    }

    @Test("resolved terminal construction receives identity before pane insertion")
    func resolvedTerminalConstructionReceivesIdentityBeforePaneInsertion() throws {
        let generatedSessionID = ZmxSessionID.generateUUIDv7()
        let resolvedContent = WorkspaceResolvedPaneContent.zmxTerminal(
            lifetime: .persistent,
            zmxSessionID: generatedSessionID
        )

        let paneContent = resolvedContent.paneContent(for: PaneId.generateUUIDv7())

        guard case .terminal(let terminalState) = paneContent else {
            Issue.record("Expected terminal pane content")
            return
        }
        let stronglyTypedSessionID: ZmxSessionID = terminalState.zmxSessionID
        #expect(stronglyTypedSessionID == generatedSessionID)
    }
}
