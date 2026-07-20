import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge review source provider factory")
struct BridgeReviewSourceProviderFactoryTests {
    @Test("workspace source root is the durable provider identity")
    func workspaceSourceRootWinsOverPaneMetadata() {
        // Arrange
        let sourceRoot = URL(fileURLWithPath: "/accepted/source-root")
        let launchDirectory = URL(fileURLWithPath: "/accepted/launch-directory")
        let currentWorkingDirectory = URL(fileURLWithPath: "/accepted/current-working-directory")

        // Act
        let location = BridgeReviewSourceProviderFactory.repositoryLocation(
            source: .workspace(rootPath: sourceRoot.path, baseline: .unstaged),
            launchDirectory: launchDirectory,
            currentWorkingDirectory: currentWorkingDirectory
        )

        // Assert
        #expect(location == .workspaceSource(sourceRoot))
    }

    @Test("non-workspace sources use the accepted launch directory")
    func nonWorkspaceSourceUsesLaunchDirectory() {
        // Arrange
        let launchDirectory = URL(fileURLWithPath: "/accepted/launch-directory")
        let currentWorkingDirectory = URL(fileURLWithPath: "/accepted/current-working-directory")

        // Act
        let location = BridgeReviewSourceProviderFactory.repositoryLocation(
            source: .commit(sha: "abc123"),
            launchDirectory: launchDirectory,
            currentWorkingDirectory: currentWorkingDirectory
        )

        // Assert
        #expect(location == .launchDirectory(launchDirectory))
    }

    @Test("current working directory is the accepted fallback")
    func currentWorkingDirectoryIsFallback() {
        // Arrange
        let currentWorkingDirectory = URL(fileURLWithPath: "/accepted/current-working-directory")

        // Act
        let location = BridgeReviewSourceProviderFactory.repositoryLocation(
            source: .branchDiff(head: "feature", base: "main"),
            launchDirectory: nil,
            currentWorkingDirectory: currentWorkingDirectory
        )

        // Assert
        #expect(location == .currentWorkingDirectory(currentWorkingDirectory))
    }

    @Test("launch and current-working-directory locations create context-bearing Git providers")
    func launchAndCurrentWorkingDirectoryLocationsCreateGitProviders() async {
        // Arrange
        let launchDirectory = URL(fileURLWithPath: "/accepted/launch-directory")
        let currentWorkingDirectory = URL(fileURLWithPath: "/accepted/current-working-directory")
        let scheduler = BridgeGitReadScheduler(topology: .recoveryBaseline)
        let launchContext = BridgeGitReadContext(
            scheduler: scheduler,
            worktreeKey: BridgeGitReadWorktreeKey(token: StableKey.fromPath(launchDirectory)),
            scopeKey: BridgeGitReadScopeKey(token: "launch-pane")
        )
        let currentWorkingDirectoryContext = BridgeGitReadContext(
            scheduler: scheduler,
            worktreeKey: BridgeGitReadWorktreeKey(token: StableKey.fromPath(currentWorkingDirectory)),
            scopeKey: BridgeGitReadScopeKey(token: "cwd-pane")
        )

        // Act
        let launchProvider = BridgeReviewSourceProviderFactory.gitProvider(
            location: .launchDirectory(launchDirectory),
            gitReadContext: launchContext
        )
        let currentWorkingDirectoryProvider = BridgeReviewSourceProviderFactory.gitProvider(
            location: .currentWorkingDirectory(currentWorkingDirectory),
            gitReadContext: currentWorkingDirectoryContext
        )

        // Assert
        #expect(launchProvider is BridgeGitReviewSourceProvider)
        #expect(currentWorkingDirectoryProvider is BridgeGitReviewSourceProvider)
        await scheduler.shutdown()
    }

    @Test("missing accepted repository location is explicitly unavailable")
    func missingAcceptedRepositoryLocationIsUnavailable() async {
        // Arrange / Act
        let location = BridgeReviewSourceProviderFactory.repositoryLocation(
            source: .agentSnapshot(taskId: UUIDv7.generate(), timestamp: Date(timeIntervalSince1970: 0)),
            launchDirectory: nil,
            currentWorkingDirectory: nil
        )
        let scheduler = BridgeGitReadScheduler(topology: .recoveryBaseline)
        let context = BridgeGitReadContext(
            scheduler: scheduler,
            worktreeKey: BridgeGitReadWorktreeKey(token: "unavailable"),
            scopeKey: BridgeGitReadScopeKey(token: "unavailable-pane")
        )
        let provider = BridgeReviewSourceProviderFactory.gitProvider(
            location: location,
            gitReadContext: context
        )

        // Assert
        #expect(location == .unavailable)
        #expect(provider is BridgeUnavailableReviewSourceProvider)
        await scheduler.shutdown()
    }
}
