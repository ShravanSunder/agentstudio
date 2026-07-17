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
        let worktreePath = bridgeWorktreePath(for: pane, state: state)
        return BridgeReviewSourceProviderFactory.gitProvider(
            repositoryPath: worktreePath,
            gitReadContext: bridgeGitReadContext(for: pane, state: state)
        )
    }

    func bridgeGitReadContext(
        for pane: Pane,
        state: BridgePaneState
    ) -> BridgeGitReadContext? {
        let resolvedWorktree = resolvedWorktreeContext(for: pane)?.worktree
        guard let worktreePath = resolvedWorktree?.path ?? bridgeWorkspaceSourcePath(from: state.source)
        else { return nil }
        return BridgeGitReadContext(
            scheduler: bridgeGitReadScheduler,
            worktreeKey: BridgeGitReadWorktreeKey(
                token: resolvedWorktree?.stableKey ?? StableKey.fromPath(worktreePath)
            ),
            scopeKey: BridgeGitReadScopeKey(token: pane.id.uuidString)
        )
    }

    private func bridgeWorktreePath(for pane: Pane, state: BridgePaneState) -> URL? {
        resolvedWorktreeContext(for: pane)?.worktree.path
            ?? bridgeWorkspaceSourcePath(from: state.source)
    }

    private func bridgeWorkspaceSourcePath(from source: BridgePaneSource?) -> URL? {
        guard case .workspace(let rootPath, _) = source else { return nil }
        return URL(fileURLWithPath: rootPath)
    }
}
