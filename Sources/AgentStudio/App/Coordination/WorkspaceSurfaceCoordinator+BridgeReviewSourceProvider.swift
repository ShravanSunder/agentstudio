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
        let worktreePath =
            resolvedWorktreeContext(for: pane)?.worktree.path
            ?? bridgeWorkspaceSourcePath(from: state.source)
        return BridgeReviewSourceProviderFactory.gitProvider(repositoryPath: worktreePath)
    }

    private func bridgeWorkspaceSourcePath(from source: BridgePaneSource?) -> URL? {
        guard case .workspace(let rootPath, _) = source else { return nil }
        return URL(fileURLWithPath: rootPath)
    }
}
