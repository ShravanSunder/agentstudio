import Foundation
import Testing

@Suite("Prepared Bridge mount topology boundary")
struct PreparedBridgeMountTopologyBoundaryTests {
    @Test("prepared Bridge provider and mount path use only accepted pane values")
    func preparedBridgeProviderAndMountPathUseOnlyAcceptedPaneValues() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let providerSource = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+BridgeReviewSourceProvider.swift"
            ),
            encoding: .utf8
        )
        let mountSource = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+NonterminalContentMounting.swift"
            ),
            encoding: .utf8
        )
        let bridgeLifecycleSource = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+BridgeViewLifecycle.swift"
            ),
            encoding: .utf8
        )
        let viewLifecycleSource = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ViewLifecycle.swift"
            ),
            encoding: .utf8
        )
        let admissionSource = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/App/Coordination/PreparedNonterminalMountAdmissionPort.swift"
            ),
            encoding: .utf8
        )
        let forbiddenTopologyTerms = [
            "resolvedWorktreeContext(",
            "repositoryTopologyAtom",
            "repoAndWorktree(",
            ".repo(",
            ".worktree(",
        ]

        // Act / Assert
        for forbiddenTopologyTerm in forbiddenTopologyTerms {
            #expect(
                !providerSource.contains(forbiddenTopologyTerm),
                "Prepared Bridge provider path contains live topology dependency: \(forbiddenTopologyTerm)"
            )
            #expect(
                !mountSource.contains(forbiddenTopologyTerm),
                "Prepared nonterminal mount path contains live topology dependency: \(forbiddenTopologyTerm)"
            )
            #expect(
                !admissionSource.contains(forbiddenTopologyTerm),
                "Prepared nonterminal admission path contains live topology dependency: \(forbiddenTopologyTerm)"
            )
        }

        #expect(providerSource.contains("source: state.source"))
        #expect(providerSource.contains("launchDirectory: pane.metadata.launchDirectory"))
        #expect(providerSource.contains("currentWorkingDirectory: pane.metadata.cwd"))
        #expect(providerSource.contains("StableKey.fromPath(repositoryURL)"))
        #expect(providerSource.contains("scopeKey: BridgeGitReadScopeKey(token: pane.id.uuidString)"))
        #expect(mountSource.contains("func mountPreparedNonterminalContent("))
        #expect(bridgeLifecycleSource.contains("bridgeReviewSourceProvider(for: pane, state: state)"))
        #expect(
            viewLifecycleSource.contains(
                "case .webview, .codeViewer, .bridgePanel, .unsupported:\n            return mountCurrentNonterminalContent(pane: pane)"
            )
        )
        #expect(admissionSource.contains("PreparedNonterminalMountAdmissionPort"))
        #expect(admissionSource.contains("claimPreparedContentMount("))
        #expect(admissionSource.contains("owner: .nonterminal"))
        #expect(admissionSource.contains("generation: generation"))
        #expect(admissionSource.contains("mountPreparedNonterminalContent(pane: descriptor.pane)"))
    }
}
