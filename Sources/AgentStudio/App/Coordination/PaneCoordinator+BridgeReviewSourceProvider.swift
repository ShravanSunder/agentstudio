import Foundation

@MainActor
extension PaneCoordinator {
    func bridgeReviewSourceProvider(
        for pane: Pane,
        state: BridgePaneState
    ) -> any BridgeReviewSourceProvider {
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
