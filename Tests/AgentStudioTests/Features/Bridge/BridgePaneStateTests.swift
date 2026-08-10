import AgentStudioCore
import Foundation
import Testing

@testable import AgentStudioBridge

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
            source: .workspace(
                rootPath: "/tmp/repo",
                baseline: .ref(name: "HEAD~1")
            )
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(BridgePaneState.self, from: data)
        #expect(decoded == state)
    }

    @Test
    func test_codable_roundTrip_preservesContributionTargetsAndNarrowBaselines() throws {
        let baselines: [WorkspaceBaseline?] = [
            .localDefaultBranch(branchName: "main"),
            .originDefaultBranch(remoteName: "origin", branchName: "main"),
            .branch(name: "feature/review"),
            .commit(oid: "0123456789abcdef0123456789abcdef01234567"),
            .ref(name: "v1.2.3"),
            .headMinusOne,
            .staged,
            .unstaged,
            nil,
        ]
        let states = baselines.map { baseline in
            BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: "/tmp/repo", baseline: baseline)
            )
        }

        for state in states {
            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(BridgePaneState.self, from: data)
            #expect(decoded == state)
        }
    }

    @Test
    func test_codable_emitsTargetOnlyWorkspacePayloadForSelectedContribution() throws {
        let state = BridgePaneState(
            panelKind: .diffViewer,
            source: .workspace(
                rootPath: "/tmp/repo",
                baseline: .localDefaultBranch(branchName: "develop")
            )
        )

        let data = try JSONEncoder().encode(state)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let source = try #require(json["source"] as? [String: Any])
        let workspace = try #require(source["workspace"] as? [String: Any])

        let target = try #require(workspace["comparisonTarget"] as? [String: Any])
        #expect(target["kind"] as? String == "localDefaultBranch")
        #expect(target["branchName"] as? String == "develop")
        #expect(workspace["baseline"] == nil)
    }

    @Test(arguments: legacyWorkspaceIntentCases)
    func test_codable_decodesLegacyWorkspacePayload(
        legacyJSON: String,
        expectedBaseline: WorkspaceBaseline?
    ) throws {
        let json = """
            {
              "panelKind": "diffViewer",
              "source": {
                "workspace": {
                  "rootPath": "/tmp/repo",
                  "baseline": \(legacyJSON)
                }
              }
            }
            """

        let decoded = try JSONDecoder().decode(BridgePaneState.self, from: Data(json.utf8))

        #expect(
            decoded.source
                == .workspace(rootPath: "/tmp/repo", baseline: expectedBaseline)
        )
    }

    @Test(arguments: malformedLegacyWorkspaceBaselines)
    func test_codable_rejectsMalformedKeyedLegacyWorkspaceBaseline(
        legacyJSON: String
    ) {
        let json = """
            {
              "panelKind": "diffViewer",
              "source": {
                "workspace": {
                  "rootPath": "/tmp/repo",
                  "baseline": \(legacyJSON)
                }
              }
            }
            """

        #expect(throws: Error.self) {
            _ = try JSONDecoder().decode(BridgePaneState.self, from: Data(json.utf8))
        }
    }

    @Test
    func test_codable_rejectsMultipleOuterSourceCases() {
        let json = """
            {
              "panelKind": "diffViewer",
              "source": {
                "commit": { "sha": "abc123" },
                "branchDiff": { "head": "feature", "base": "main" }
              }
            }
            """

        #expect(throws: Error.self) {
            _ = try JSONDecoder().decode(BridgePaneState.self, from: Data(json.utf8))
        }
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
    func test_paneContent_bridgePanel_unknownVersion_throws() throws {
        // Strict canonical decode rejects malformed bridge panel state.
        let json = """
            {"type":"bridgePanel","version":99,"state":{"unknownField":"value"}}
            """
        let data = Data(json.utf8)

        #expect(throws: Error.self) {
            _ = try JSONDecoder().decode(PaneContent.self, from: data)
        }
    }
}

private let legacyWorkspaceIntentCases: [(String, WorkspaceBaseline?)] = [
    (
        #"{"kind":"localDefaultBranch","branchName":"hotfix/urgent"}"#,
        nil
    ),
    (
        #"{"kind":"originDefaultBranch","remoteName":"origin","branchName":"master"}"#,
        .originDefaultBranch(remoteName: "origin", branchName: "master")
    ),
    (
        #"{"kind":"branch","name":"stack/base"}"#,
        .branch(name: "stack/base")
    ),
    (
        #"{"kind":"commit","oid":"0123456789abcdef0123456789abcdef01234567"}"#,
        .commit(oid: "0123456789abcdef0123456789abcdef01234567")
    ),
    (
        #"{"kind":"ref","name":"refs/tags/v1.2.3"}"#,
        .ref(name: "refs/tags/v1.2.3")
    ),
    (
        #"{"kind":"ref","name":"main"}"#,
        .ref(name: "main")
    ),
    (
        #"{"kind":"ref","name":"HEAD"}"#,
        nil
    ),
    (
        #"{"kind":"headMinusOne"}"#,
        .headMinusOne
    ),
    (
        #"{"kind":"staged"}"#,
        .staged
    ),
    (
        #"{"kind":"unstaged"}"#,
        .unstaged
    ),
    (
        #""localDefaultBranch""#,
        nil
    ),
    (
        #""originDefaultBranch""#,
        .originDefaultBranch(remoteName: "origin", branchName: "main")
    ),
    (
        #""branch""#,
        .ref(name: "branch")
    ),
    (
        #""ref""#,
        .ref(name: "ref")
    ),
    (
        #""headMinusOne""#,
        .headMinusOne
    ),
    (
        #""HEAD""#,
        nil
    ),
    (
        #""main""#,
        nil
    ),
    (
        #""staged""#,
        .staged
    ),
    (
        #""unstaged""#,
        .unstaged
    ),
]

private let malformedLegacyWorkspaceBaselines: [String] = [
    #"{"kind":"localDefaultBranch"}"#,
    #"{"kind":"originDefaultBranch","branchName":"main"}"#,
    #"{"kind":"originDefaultBranch","remoteName":"origin"}"#,
    #"{"kind":"branch"}"#,
    #"{"kind":"commit"}"#,
    #"{"kind":"commit","oid":"abc123"}"#,
    #"{"kind":"commit","oid":"gggggggggggggggggggggggggggggggggggggggg"}"#,
    #"{"kind":"ref"}"#,
    #"{"kind":"unknown"}"#,
]
