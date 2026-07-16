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
        let location = BridgeReviewSourceProviderFactory.repositoryLocation(
            source: state.source,
            launchDirectory: pane.metadata.launchDirectory,
            currentWorkingDirectory: pane.metadata.cwd
        )
        return BridgeReviewSourceProviderFactory.gitProvider(location: location)
    }
}
