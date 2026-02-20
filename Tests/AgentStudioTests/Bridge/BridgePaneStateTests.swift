import XCTest
@testable import AgentStudio

/// Tests for BridgePaneState Codable round-trip and Hashable conformance.
///
/// BridgePaneState is the persistence model for bridge-backed panels (diff viewer,
/// code review, etc.). These tests verify that all BridgePaneSource variants
/// survive JSON encode/decode and that equality/hashing work correctly.
final class BridgePaneStateTests: XCTestCase {

    // MARK: - Codable Round-Trip

    func test_codable_roundTrip_diffViewer() throws {
        let state = BridgePaneState(panelKind: .diffViewer, source: nil)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(BridgePaneState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func test_codable_roundTrip_with_commitSource() throws {
        let state = BridgePaneState(
            panelKind: .diffViewer,
            source: .commit(sha: "abc123")
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(BridgePaneState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func test_codable_roundTrip_with_branchDiffSource() throws {
        let state = BridgePaneState(
            panelKind: .diffViewer,
            source: .branchDiff(head: "feature", base: "main")
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(BridgePaneState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func test_codable_roundTrip_with_workspaceSource() throws {
        let state = BridgePaneState(
            panelKind: .diffViewer,
            source: .workspace(rootPath: "/tmp/repo", baseline: .headMinusOne)
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(BridgePaneState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func test_codable_roundTrip_with_agentSnapshotSource() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1000000)
        let state = BridgePaneState(
            panelKind: .diffViewer,
            source: .agentSnapshot(taskId: id, timestamp: date)
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(BridgePaneState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    // MARK: - Hashable

    func test_hashable() {
        let a = BridgePaneState(panelKind: .diffViewer, source: nil)
        let b = BridgePaneState(panelKind: .diffViewer, source: nil)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func test_different_sources_not_equal() {
        let a = BridgePaneState(panelKind: .diffViewer, source: .commit(sha: "abc"))
        let b = BridgePaneState(panelKind: .diffViewer, source: .commit(sha: "def"))
        XCTAssertNotEqual(a, b)
    }
}
