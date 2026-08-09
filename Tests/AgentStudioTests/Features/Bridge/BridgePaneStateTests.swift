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
                comparisonIntent: .init(
                    activeKind: .contribution,
                    contributionTarget: .ref(name: "HEAD~1")
                )
            )
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(BridgePaneState.self, from: data)
        #expect(decoded == state)
    }

    @Test
    func test_codable_roundTrip_preservesActiveKindAndRetainedContributionTarget() throws {
        let targets: [WorkspaceReviewContributionTarget] = [
            .localDefaultBranch(branchName: "main"),
            .originDefaultBranch(remoteName: "origin", branchName: "main"),
            .branch(name: "feature/review"),
            .ref(name: "v1.2.3"),
        ]
        let states = WorkspaceReviewComparisonIntent.ActiveKind.allCases.flatMap { activeKind in
            targets.map { target in
                BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(
                        rootPath: "/tmp/repo",
                        comparisonIntent: .init(
                            activeKind: activeKind,
                            contributionTarget: target
                        )
                    )
                )
            }
        }

        for state in states {
            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(BridgePaneState.self, from: data)
            #expect(decoded == state)
        }
    }

    @Test
    func test_codable_emitsOnlyComparisonIntentWorkspacePayload() throws {
        let state = BridgePaneState(
            panelKind: .diffViewer,
            source: .workspace(
                rootPath: "/tmp/repo",
                comparisonIntent: .init(
                    activeKind: .stagedOnly,
                    contributionTarget: .branch(name: "stack/base")
                )
            )
        )

        let data = try JSONEncoder().encode(state)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let source = try #require(json["source"] as? [String: Any])
        let workspace = try #require(source["workspace"] as? [String: Any])

        #expect(workspace["comparisonIntent"] != nil)
        #expect(workspace["baseline"] == nil)
    }

    @Test(arguments: legacyWorkspaceIntentCases)
    func test_codable_decodesLegacyWorkspacePayload(
        legacyJSON: String,
        expectedIntent: WorkspaceReviewComparisonIntent
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
                == .workspace(rootPath: "/tmp/repo", comparisonIntent: expectedIntent)
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

private let legacyWorkspaceIntentCases: [(String, WorkspaceReviewComparisonIntent)] = [
    (
        #"{"kind":"localDefaultBranch","branchName":"hotfix/urgent"}"#,
        .init(activeKind: .contribution, contributionTarget: nil)
    ),
    (
        #"{"kind":"originDefaultBranch","remoteName":"origin","branchName":"master"}"#,
        .init(
            activeKind: .contribution,
            contributionTarget: .originDefaultBranch(remoteName: "origin", branchName: "master")
        )
    ),
    (
        #"{"kind":"branch","name":"stack/base"}"#,
        .init(activeKind: .contribution, contributionTarget: .branch(name: "stack/base"))
    ),
    (
        #"{"kind":"ref","name":"refs/tags/v1.2.3"}"#,
        .init(activeKind: .contribution, contributionTarget: .ref(name: "refs/tags/v1.2.3"))
    ),
    (
        #"{"kind":"ref","name":"HEAD"}"#,
        .init(activeKind: .contribution, contributionTarget: nil)
    ),
    (
        #"{"kind":"headMinusOne"}"#,
        .init(activeKind: .contribution, contributionTarget: .ref(name: "HEAD~1"))
    ),
    (
        #"{"kind":"staged"}"#,
        .init(activeKind: .stagedOnly, contributionTarget: nil)
    ),
    (
        #"{"kind":"unstaged"}"#,
        .init(activeKind: .unstagedOnly, contributionTarget: nil)
    ),
    (
        #""localDefaultBranch""#,
        .init(activeKind: .contribution, contributionTarget: nil)
    ),
    (
        #""originDefaultBranch""#,
        .init(
            activeKind: .contribution,
            contributionTarget: .originDefaultBranch(remoteName: "origin", branchName: "main")
        )
    ),
    (
        #""branch""#,
        .init(activeKind: .contribution, contributionTarget: .ref(name: "branch"))
    ),
    (
        #""ref""#,
        .init(activeKind: .contribution, contributionTarget: .ref(name: "ref"))
    ),
    (
        #""headMinusOne""#,
        .init(activeKind: .contribution, contributionTarget: .ref(name: "HEAD~1"))
    ),
    (
        #""HEAD""#,
        .init(activeKind: .contribution, contributionTarget: nil)
    ),
    (
        #""main""#,
        .init(activeKind: .contribution, contributionTarget: .ref(name: "main"))
    ),
    (
        #""staged""#,
        .init(activeKind: .stagedOnly, contributionTarget: nil)
    ),
    (
        #""unstaged""#,
        .init(activeKind: .unstagedOnly, contributionTarget: nil)
    ),
]

private let malformedLegacyWorkspaceBaselines: [String] = [
    #"{"kind":"localDefaultBranch"}"#,
    #"{"kind":"originDefaultBranch","branchName":"main"}"#,
    #"{"kind":"originDefaultBranch","remoteName":"origin"}"#,
    #"{"kind":"branch"}"#,
    #"{"kind":"ref"}"#,
    #"{"kind":"unknown"}"#,
]
