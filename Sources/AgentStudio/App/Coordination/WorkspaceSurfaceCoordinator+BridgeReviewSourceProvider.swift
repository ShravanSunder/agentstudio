import AgentStudioBridge
import AgentStudioCore
import Foundation

@MainActor
extension WorkspaceSurfaceCoordinator {
    func bridgeReviewSourceProvider(
        for pane: Pane,
        reviewRootPath: String?
    ) -> any BridgeReviewSourceProvider {
        #if DEBUG
            if let provider = bridgeReviewSourceProviderOverridesByPaneId[pane.id] {
                return provider
            }
        #endif
        let location = bridgeReviewRepositoryLocation(for: pane, reviewRootPath: reviewRootPath)
        return BridgeReviewSourceProviderFactory.gitProvider(
            location: location,
            gitReadContext: bridgeGitReadContext(for: pane, repositoryLocation: location),
            statusPhysicalGate: gitStatusPhysicalGate
        )
    }

    func bridgeGitReadContext(
        for pane: Pane,
        reviewRootPath: String?
    ) -> BridgeGitReadContext? {
        bridgeGitReadContext(
            for: pane,
            repositoryLocation: bridgeReviewRepositoryLocation(for: pane, reviewRootPath: reviewRootPath)
        )
    }

    private func bridgeGitReadContext(
        for pane: Pane,
        repositoryLocation: BridgeReviewRepositoryLocation
    ) -> BridgeGitReadContext? {
        guard let repositoryURL = repositoryLocation.repositoryURL else { return nil }
        return BridgeGitReadContext(
            scheduler: bridgeGitReadScheduler,
            worktreeKey: BridgeGitReadWorktreeKey(
                token: StableKey.fromPath(repositoryURL)
            ),
            scopeKey: BridgeGitReadScopeKey(token: pane.id.uuidString)
        )
    }

    private func bridgeReviewRepositoryLocation(
        for pane: Pane,
        reviewRootPath: String?
    ) -> BridgeReviewRepositoryLocation {
        BridgeReviewSourceProviderFactory.repositoryLocation(
            reviewRootPath: reviewRootPath,
            launchDirectory: pane.metadata.launchDirectory,
            currentWorkingDirectory: pane.metadata.cwd
        )
    }
}
