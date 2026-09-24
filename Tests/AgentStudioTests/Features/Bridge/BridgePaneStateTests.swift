import AgentStudioCore
import Foundation
import Testing

@testable import AgentStudioBridge

/// Tests for the source-free `BridgePaneState` payload and the legacy source
/// conversion DTO that reads the retired `source` field during the ordered
/// navigation import.
@Suite(.serialized)
final class BridgePaneStateTests {

    // MARK: - Source-free payload

    @Test
    func test_codable_roundTrip_panelKinds() throws {
        for panelKind in [BridgePanelKind.diffViewer, .fileViewer] {
            let state = BridgePaneState(panelKind: panelKind)
            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(BridgePaneState.self, from: data)
            #expect(decoded == state)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["source"] == nil, "live pane state never writes a source selection")
        }
    }

    @Test
    func test_decodingLegacyPayloadIgnoresSourceField() throws {
        let json = """
            {"panelKind":"diffViewer","source":{"workspace":{"rootPath":"/tmp/repo"}}}
            """

        let decoded = try JSONDecoder().decode(BridgePaneState.self, from: Data(json.utf8))

        #expect(decoded == BridgePaneState(panelKind: .diffViewer))
    }

    @Test
    func test_codable_roundTrip_preservesBranchTipComparisonBasis() throws {
        let target = WorkspaceReviewContributionTarget.branch(
            name: "review/selected-target",
            basis: .branchTip
        )

        let data = try JSONEncoder().encode(target)

        #expect(
            try JSONDecoder().decode(WorkspaceReviewContributionTarget.self, from: data) == target
        )
    }

    @Test
    func test_codable_defaultsLegacyTargetBasisToCommonCommit() throws {
        let target = try JSONDecoder().decode(
            WorkspaceReviewContributionTarget.self,
            from: Data(#"{"kind":"branch","name":"review/legacy"}"#.utf8)
        )

        #expect(target == .branch(name: "review/legacy", basis: .commonCommit))
    }

    @Test(arguments: legacyWorkspaceIntentCases)
    func test_legacyDTO_decodesLegacyWorkspacePayload(
        legacyJSON: String,
        expectedBaseline: WorkspaceBaseline?
    ) throws {
        let json = """
            {"workspace":{"rootPath":"/tmp/repo","baseline":\(legacyJSON)}}
            """

        let decoded = try JSONDecoder().decode(LegacyBridgePaneSourceDTO.self, from: Data(json.utf8))

        #expect(decoded == .workspace(rootPath: "/tmp/repo", baseline: expectedBaseline))
    }

    @Test
    func test_legacyDTO_decodesComparisonTargetAndNonWorkspaceVariants() throws {
        let target = try JSONDecoder().decode(
            LegacyBridgePaneSourceDTO.self,
            from: Data(
                #"{"workspace":{"rootPath":"/tmp/repo","comparisonTarget":{"kind":"branch","name":"develop"}}}"#.utf8
            )
        )
        let commit = try JSONDecoder().decode(
            LegacyBridgePaneSourceDTO.self,
            from: Data(#"{"commit":{"sha":"abc123"}}"#.utf8)
        )
        let branchDiff = try JSONDecoder().decode(
            LegacyBridgePaneSourceDTO.self,
            from: Data(#"{"branchDiff":{"head":"feature","base":"main"}}"#.utf8)
        )

        #expect(target == .workspace(rootPath: "/tmp/repo", baseline: .branch(name: "develop")))
        #expect(commit == .commit(sha: "abc123"))
        #expect(commit.importedVariant == .commit)
        #expect(branchDiff == .branchDiff(head: "feature", base: "main"))
    }

    @Test(arguments: malformedLegacyWorkspaceBaselines)
    func test_legacyDTO_rejectsMalformedKeyedLegacyWorkspaceBaseline(
        legacyJSON: String
    ) {
        let json = """
            {"workspace":{"rootPath":"/tmp/repo","baseline":\(legacyJSON)}}
            """

        #expect(throws: Error.self) {
            _ = try JSONDecoder().decode(LegacyBridgePaneSourceDTO.self, from: Data(json.utf8))
        }
    }

    @Test
    func test_legacyDTO_rejectsMultipleOuterSourceCases() {
        let json = """
            {"commit":{"sha":"abc123"},"branchDiff":{"head":"feature","base":"main"}}
            """

        #expect(throws: Error.self) {
            _ = try JSONDecoder().decode(LegacyBridgePaneSourceDTO.self, from: Data(json.utf8))
        }
    }

    // MARK: - PaneContent.bridgePanel Codable Round-Trip

    @Test
    func test_paneContent_bridgePanel_codable_roundTrip() throws {
        let bridgeState = BridgePaneState(panelKind: .fileViewer)
        let content = PaneContent.bridgePanel(bridgeState)
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(PaneContent.self, from: data)

        #expect(decoded == content)
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
