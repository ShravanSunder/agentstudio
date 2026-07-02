import Foundation
import Testing

@testable import AgentStudio

struct BridgeWorktreeFileSurfaceContractTests {
    @Test("shared Worktree/File open-source input fixture decodes strictly in Swift")
    func sharedWorktreeFileOpenSourceInputFixtureDecodesStrictlyInSwift() throws {
        let spec = try decodeFixture(
            BridgeWorktreeFileSurfaceSourceSpec.self,
            relativePath: "Tests/BridgeContractFixtures/valid/worktree-file-open-source-spec.json"
        )

        #expect(spec.clientRequestId == "request-1")
        #expect(spec.repoId.uuidString == "00000000-0000-7000-8000-000000000001")
        #expect(spec.worktreeId.uuidString == "00000000-0000-7000-8000-000000000002")
        #expect(spec.rootPathToken == "stable-root-token-1")
        #expect(spec.pathScope == ["Sources/App"])
        #expect(spec.includeStatuses == true)
        #expect(spec.includeComments == false)
        #expect(spec.includeAgentComms == false)
        #expect(spec.freshness == .live)
    }

    @Test("shared Worktree/File open-source input fixture rejects unknown legacy fields")
    func sharedWorktreeFileOpenSourceInputFixtureRejectsUnknownLegacyFields() throws {
        let data = try fixtureData(
            relativePath: "Tests/BridgeContractFixtures/invalid/worktree-file-open-source-spec-extra-field.json"
        )

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(BridgeWorktreeFileSurfaceSourceSpec.self, from: data)
        }
    }

    @Test("shared Worktree/File open-source outcome fixture decodes and re-encodes strictly in Swift")
    func sharedWorktreeFileOpenSourceOutcomeFixtureDecodesAndReencodesStrictlyInSwift() throws {
        let outcome = try decodeFixture(
            BridgeWorktreeFileSurfaceOpenSourceOutcome.self,
            relativePath: "Tests/BridgeContractFixtures/valid/worktree-file-open-source-outcome.json"
        )

        #expect(outcome.status == "accepted")
        #expect(outcome.protocolId == "worktree-file")
        #expect(outcome.streamId == "worktree-file:00000000-0000-7000-8000-000000000003")
        #expect(outcome.generation == 1)

        let encoded = try JSONEncoder().encode(outcome)
        let decoded = try JSONDecoder().decode(BridgeWorktreeFileSurfaceOpenSourceOutcome.self, from: encoded)
        #expect(decoded == outcome)
    }

    @Test("shared Worktree/File open-source outcome rejects wrong protocol")
    func sharedWorktreeFileOpenSourceOutcomeRejectsWrongProtocol() throws {
        let data = try fixtureData(
            relativePath: "Tests/BridgeContractFixtures/invalid/worktree-file-open-source-outcome-wrong-protocol.json"
        )

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(BridgeWorktreeFileSurfaceOpenSourceOutcome.self, from: data)
        }
    }

    @Test("shared Worktree/File open-source outcome rejects unknown legacy fields")
    func sharedWorktreeFileOpenSourceOutcomeRejectsUnknownLegacyFields() throws {
        let data = try fixtureData(
            relativePath: "Tests/BridgeContractFixtures/invalid/worktree-file-open-source-outcome-extra-field.json"
        )

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(BridgeWorktreeFileSurfaceOpenSourceOutcome.self, from: data)
        }
    }

    @Test("Worktree/File tree row encoding preserves explicit null parent path")
    func worktreeFileTreeRowEncodingPreservesExplicitNullParentPath() throws {
        let row = BridgeWorktreeTreeRowMetadata(
            rowId: "row:README.md",
            path: "README.md",
            name: "README.md",
            parentPath: nil,
            depth: 0,
            isDirectory: false,
            fileId: "file:README.md",
            sizeBytes: 42,
            lineCount: 2,
            changeStatus: nil
        )

        let data = try JSONEncoder().encode(row)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(object.keys.contains("parentPath"))
        #expect(object["parentPath"] is NSNull)
    }

    private func decodeFixture<TDecoded: Decodable>(
        _ type: TDecoded.Type,
        relativePath: String
    ) throws -> TDecoded {
        try JSONDecoder().decode(TDecoded.self, from: fixtureData(relativePath: relativePath))
    }

    private func fixtureData(relativePath: String) throws -> Data {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        return try Data(contentsOf: projectRoot.appending(path: relativePath))
    }
}
