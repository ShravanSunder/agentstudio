import Foundation
import Testing

@testable import AgentStudio

struct BridgeWorktreeFileSourceProviderTests {
    @Test("source spec decodes browser selector defaults")
    func sourceSpecDecodesBrowserSelectorDefaults() throws {
        let worktree = makeWorktree(rootPath: "/tmp/repo")
        let payload = Data(
            """
            {
              "clientRequestId": "request-1",
              "repoId": "\(worktree.repoId.uuidString)",
              "worktreeId": "\(worktree.id.uuidString)",
              "rootPathToken": "\(worktree.stableKey)",
              "freshness": "live"
            }
            """.utf8)

        let spec = try JSONDecoder().decode(BridgeWorktreeFileSurfaceSourceSpec.self, from: payload)

        #expect(spec.pathScope.isEmpty)
        #expect(spec.includeStatuses)
        #expect(spec.includeComments == false)
        #expect(spec.includeAgentComms == false)
    }

    @Test("source spec rejects unknown keys and explicit null defaults")
    func sourceSpecRejectsUnknownKeysAndExplicitNullDefaults() throws {
        let worktree = makeWorktree(rootPath: "/tmp/repo")
        let payloadWithExtraKey = Data(
            """
            {
              "clientRequestId": "request-1",
              "repoId": "\(worktree.repoId.uuidString)",
              "worktreeId": "\(worktree.id.uuidString)",
              "rootPathToken": "\(worktree.stableKey)",
              "freshness": "live",
              "contentAuthority": "browser-minted"
            }
            """.utf8)
        let payloadWithNullDefault = Data(
            """
            {
              "clientRequestId": "request-1",
              "repoId": "\(worktree.repoId.uuidString)",
              "worktreeId": "\(worktree.id.uuidString)",
              "rootPathToken": "\(worktree.stableKey)",
              "freshness": "live",
              "includeStatuses": null
            }
            """.utf8)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(BridgeWorktreeFileSurfaceSourceSpec.self, from: payloadWithExtraKey)
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(BridgeWorktreeFileSurfaceSourceSpec.self, from: payloadWithNullDefault)
        }
    }

    @Test("source spec rejects blank browser selector authority fields")
    func sourceSpecRejectsBlankBrowserSelectorAuthorityFields() throws {
        let worktree = makeWorktree(rootPath: "/tmp/repo")
        let blankClientRequestId = sourceSpecPayload(
            worktree: worktree,
            clientRequestId: "",
            rootPathToken: worktree.stableKey,
            cwdScope: nil,
            pathScope: []
        )
        let blankRootPathToken = sourceSpecPayload(
            worktree: worktree,
            clientRequestId: "request-1",
            rootPathToken: "",
            cwdScope: nil,
            pathScope: []
        )
        let whitespaceCwdScope = sourceSpecPayload(
            worktree: worktree,
            clientRequestId: "request-1",
            rootPathToken: worktree.stableKey,
            cwdScope: "   ",
            pathScope: []
        )
        let blankPathScope = sourceSpecPayload(
            worktree: worktree,
            clientRequestId: "request-1",
            rootPathToken: worktree.stableKey,
            cwdScope: nil,
            pathScope: [""]
        )

        for payload in [blankClientRequestId, blankRootPathToken, whitespaceCwdScope, blankPathScope] {
            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder().decode(BridgeWorktreeFileSurfaceSourceSpec.self, from: payload)
            }
        }
    }

    @Test("open source mints provider identity and canonical path scope")
    func openSourceMintsProviderIdentityAndCanonicalPathScope() throws {
        let worktree = makeWorktree(rootPath: "/tmp/repo")
        let spec = BridgeWorktreeFileSurfaceSourceSpec(
            clientRequestId: "request-1",
            repoId: worktree.repoId,
            worktreeId: worktree.id,
            rootPathToken: worktree.stableKey,
            cwdScope: "Sources/../Sources/App",
            pathScope: ["./Views/ContentView.swift"],
            includeStatuses: true,
            includeComments: false,
            includeAgentComms: false,
            freshness: .live
        )

        let opened = try BridgeWorktreeFileSourceProvider.openSource(
            spec: spec,
            worktree: worktree,
            subscriptionGeneration: 7
        )

        #expect(opened.source.sourceId == "worktree-\(worktree.id.uuidString)-7")
        #expect(opened.source.repoId == worktree.repoId.uuidString)
        #expect(opened.source.worktreeId == worktree.id.uuidString)
        #expect(opened.source.subscriptionGeneration == 7)
        #expect(opened.source.sourceCursor == "generation-7")
        #expect(opened.canonicalCwdScope == "Sources/App")
        #expect(opened.canonicalPathScope == ["Sources/App/Views/ContentView.swift"])
        #expect(opened.includeStatuses)
    }

    @Test("open source rejects browser selector that escapes worktree root")
    func openSourceRejectsBrowserSelectorThatEscapesWorktreeRoot() throws {
        let worktree = makeWorktree(rootPath: "/tmp/repo")
        let spec = BridgeWorktreeFileSurfaceSourceSpec(
            clientRequestId: "request-1",
            repoId: worktree.repoId,
            worktreeId: worktree.id,
            rootPathToken: worktree.stableKey,
            cwdScope: nil,
            pathScope: ["../outside.swift"],
            includeStatuses: true,
            includeComments: false,
            includeAgentComms: false,
            freshness: .live
        )

        #expect(throws: BridgeWorktreeFileSourceProviderError.selectorEscapesRoot) {
            _ = try BridgeWorktreeFileSourceProvider.openSource(
                spec: spec,
                worktree: worktree,
                subscriptionGeneration: 1
            )
        }
    }

    @Test("open source rejects absolute selector with case-variant sibling root")
    func openSourceRejectsAbsoluteSelectorWithCaseVariantSiblingRoot() throws {
        let worktree = makeWorktree(rootPath: "/tmp/repo")
        let spec = BridgeWorktreeFileSurfaceSourceSpec(
            clientRequestId: "request-1",
            repoId: worktree.repoId,
            worktreeId: worktree.id,
            rootPathToken: worktree.stableKey,
            cwdScope: "/tmp/Repo",
            pathScope: ["secret.swift"],
            includeStatuses: true,
            includeComments: false,
            includeAgentComms: false,
            freshness: .live
        )

        #expect(throws: BridgeWorktreeFileSourceProviderError.selectorEscapesRoot) {
            _ = try BridgeWorktreeFileSourceProvider.openSource(
                spec: spec,
                worktree: worktree,
                subscriptionGeneration: 1
            )
        }
    }

    @Test("open source preserves supported selector flags for downstream snapshot work")
    func openSourcePreservesSupportedSelectorFlagsForDownstreamSnapshotWork() throws {
        let worktree = makeWorktree(rootPath: "/tmp/repo")
        let spec = BridgeWorktreeFileSurfaceSourceSpec(
            clientRequestId: "request-1",
            repoId: worktree.repoId,
            worktreeId: worktree.id,
            rootPathToken: worktree.stableKey,
            cwdScope: nil,
            pathScope: [],
            includeStatuses: false,
            includeComments: false,
            includeAgentComms: false,
            freshness: .live
        )

        let opened = try BridgeWorktreeFileSourceProvider.openSource(
            spec: spec,
            worktree: worktree,
            subscriptionGeneration: 1
        )

        #expect(opened.includeStatuses == false)
    }

    @Test("open source rejects stale root token without leaking raw paths")
    func openSourceRejectsStaleRootTokenWithoutLeakingRawPaths() throws {
        let worktree = makeWorktree(rootPath: "/tmp/private/repo")
        let spec = BridgeWorktreeFileSurfaceSourceSpec(
            clientRequestId: "request-1",
            repoId: worktree.repoId,
            worktreeId: worktree.id,
            rootPathToken: "stale-root-token",
            cwdScope: nil,
            pathScope: [],
            includeStatuses: true,
            includeComments: false,
            includeAgentComms: false,
            freshness: .live
        )

        do {
            _ = try BridgeWorktreeFileSourceProvider.openSource(
                spec: spec,
                worktree: worktree,
                subscriptionGeneration: 1
            )
            Issue.record("Expected stale root token to throw")
        } catch let error as BridgeWorktreeFileSourceProviderError {
            #expect(error == .rootTokenMismatch)
            #expect(String(describing: error).contains("/tmp/private/repo") == false)
            #expect(String(describing: error).contains("stale-root-token") == false)
        }
    }

    @Test("open source rejects unsupported comments and agent comms flags explicitly")
    func openSourceRejectsUnsupportedCommentsAndAgentCommsFlagsExplicitly() throws {
        let worktree = makeWorktree(rootPath: "/tmp/repo")
        let spec = BridgeWorktreeFileSurfaceSourceSpec(
            clientRequestId: "request-1",
            repoId: worktree.repoId,
            worktreeId: worktree.id,
            rootPathToken: worktree.stableKey,
            cwdScope: nil,
            pathScope: [],
            includeStatuses: true,
            includeComments: true,
            includeAgentComms: true,
            freshness: .live
        )

        #expect(throws: BridgeWorktreeFileSourceProviderError.unsupportedReservedContract) {
            _ = try BridgeWorktreeFileSourceProvider.openSource(
                spec: spec,
                worktree: worktree,
                subscriptionGeneration: 1
            )
        }
    }

    private func makeWorktree(rootPath: String) -> Worktree {
        Worktree(
            repoId: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
            name: "repo",
            path: URL(fileURLWithPath: rootPath)
        )
    }

    private func sourceSpecPayload(
        worktree: Worktree,
        clientRequestId: String,
        rootPathToken: String,
        cwdScope: String?,
        pathScope: [String]
    ) -> Data {
        var payload: [String: Any] = [
            "clientRequestId": clientRequestId,
            "repoId": worktree.repoId.uuidString,
            "worktreeId": worktree.id.uuidString,
            "rootPathToken": rootPathToken,
            "pathScope": pathScope,
            "freshness": "live",
        ]
        if let cwdScope {
            payload["cwdScope"] = cwdScope
        }
        return try! JSONSerialization.data(withJSONObject: payload)
    }
}
