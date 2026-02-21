import Testing
import Foundation

@testable import AgentStudio

/// Tests for BridgePaneState Codable round-trip and Hashable conformance.
///
/// BridgePaneState is the persistence model for bridge-backed panels (diff viewer,
/// code review, etc.). These tests verify that all BridgePaneSource variants
/// survive JSON encode/decode and that equality/hashing work correctly.
@Suite(.serialized)
final class BridgePaneStateTests {

    // MARK: - Codable Round-Trip

    @Test
    func test_codable_roundTrip_diffViewer() throws {
        let state = BridgePaneState(panelKind: .diffViewer, source: nil)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(BridgePaneState.self, from: data)
        #expect(decoded == state)
    }

    @Test
    func test_codable_roundTrip_with_commitSource() throws {
        let state = BridgePaneState(
            panelKind: .diffViewer,
            source: .commit(sha: "abc123")
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(BridgePaneState.self, from: data)
        #expect(decoded == state)
    }

    @Test
    func test_codable_roundTrip_with_branchDiffSource() throws {
        let state = BridgePaneState(
            panelKind: .diffViewer,
            source: .branchDiff(head: "feature", base: "main")
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(BridgePaneState.self, from: data)
        #expect(decoded == state)
    }

    @Test
    func test_codable_roundTrip_with_workspaceSource() throws {
        let state = BridgePaneState(
            panelKind: .diffViewer,
            source: .workspace(rootPath: "/tmp/repo", baseline: .headMinusOne)
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(BridgePaneState.self, from: data)
        #expect(decoded == state)
    }

    @Test
    func test_codable_roundTrip_with_agentSnapshotSource() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_000_000)
        let state = BridgePaneState(
            panelKind: .diffViewer,
            source: .agentSnapshot(taskId: id, timestamp: date)
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(BridgePaneState.self, from: data)
        #expect(decoded == state)
    }

    // MARK: - Hashable

    @Test
    func test_hashable() {
        let a = BridgePaneState(panelKind: .diffViewer, source: nil)
        let b = BridgePaneState(panelKind: .diffViewer, source: nil)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test
    func test_different_sources_not_equal() {
        let a = BridgePaneState(panelKind: .diffViewer, source: .commit(sha: "abc"))
        let b = BridgePaneState(panelKind: .diffViewer, source: .commit(sha: "def"))
        #expect(a != b)
    }

    // MARK: - PaneContent.bridgePanel Codable Round-Trip

    @Test
    func test_paneContent_bridgePanel_codable_roundTrip() throws {
        let bridgeState = BridgePaneState(
            panelKind: .diffViewer,
            source: .branchDiff(head: "feature", base: "main")
        )
        let content = PaneContent.bridgePanel(bridgeState)
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(PaneContent.self, from: data)

        let decodedState = try #require(
            {
                if case .bridgePanel(let value) = decoded {
                    return value
                }
                return nil
            }(),
            "Expected .bridgePanel, got \(decoded)"
        )
        #expect(decodedState == bridgeState)
    }

    @Test
    func test_paneContent_bridgePanel_unknownVersion_decodesAsUnsupported() throws {
        // Simulate a future version that adds unknown fields by manually crafting JSON
        // with an unrecognized state shape that will fail BridgePaneState decoding
        let json = """
            {"type":"bridgePanel","version":99,"state":{"unknownField":"value"}}
            """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(PaneContent.self, from: data)

        let unsupported = try #require(
            {
                if case .unsupported(let content) = decoded {
                    return content
                }
                return nil
            }(),
            "Expected .unsupported for malformed bridgePanel state, got \(decoded)"
        )
        #expect(unsupported.type == "bridgePanel")
        #expect(unsupported.version == 99)
    }
}
