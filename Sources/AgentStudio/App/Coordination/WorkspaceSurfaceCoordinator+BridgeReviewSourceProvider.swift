import Foundation

@MainActor
extension WorkspaceSurfaceCoordinator {
    func bridgeReviewSourceProvider(
        for pane: Pane,
        state: BridgePaneState
    ) -> any BridgeReviewSourceProvider {
        #if DEBUG
            if let provider = bridgeReviewSourceProviderOverridesByPaneId[pane.id] {
                return provider
            }
        #endif
        let location = bridgeReviewRepositoryLocation(for: pane, state: state)
        return BridgeReviewSourceProviderFactory.gitProvider(
            location: location,
            gitReadContext: bridgeGitReadContext(for: pane, repositoryLocation: location)
        )
    }

    func bridgeGitReadContext(
        for pane: Pane,
        state: BridgePaneState
    ) -> BridgeGitReadContext? {
        bridgeGitReadContext(
            for: pane,
            repositoryLocation: bridgeReviewRepositoryLocation(for: pane, state: state)
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
        state: BridgePaneState
    ) -> BridgeReviewRepositoryLocation {
        BridgeReviewSourceProviderFactory.repositoryLocation(
            source: state.source,
            launchDirectory: pane.metadata.launchDirectory,
            currentWorkingDirectory: pane.metadata.cwd
        )
    }
}
