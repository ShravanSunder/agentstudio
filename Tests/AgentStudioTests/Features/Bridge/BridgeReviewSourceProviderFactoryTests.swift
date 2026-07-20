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

    @Test("missing accepted repository location is explicitly unavailable")
    func missingAcceptedRepositoryLocationIsUnavailable() {
        // Arrange / Act
        let location = BridgeReviewSourceProviderFactory.repositoryLocation(
            source: .agentSnapshot(taskId: UUIDv7.generate(), timestamp: Date(timeIntervalSince1970: 0)),
            launchDirectory: nil,
            currentWorkingDirectory: nil
        )
        let provider = BridgeReviewSourceProviderFactory.gitProvider(location: location)

        // Assert
        #expect(location == .unavailable)
        #expect(provider is BridgeUnavailableReviewSourceProvider)
    }
}
