import AgentStudioCore
import Foundation

@MainActor
enum PanePullRequestToolbarActionFactory {
    static func make(
        paneId: UUID,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        openExternalURL: @escaping @MainActor @Sendable (URL) -> Bool
    ) -> PaneSurfaceToolbarAction? {
        guard
            GitHubWebviewLaunchResolver.hasResolvableWorktreeContext(
                for: paneId,
                store: store
            )
        else { return nil }

        let exactPullRequestURL = GitHubWebviewLaunchResolver.pullRequestsURL(
            for: paneId,
            store: store,
            repoCache: repoCache
        )
        let actionSpec = LocalActionSpec.openPullRequest.actionSpec
        let isEnabled = exactPullRequestURL != nil
        return PaneSurfaceToolbarAction(
            state: PaneSurfaceToolbarAction.State(
                label: actionSpec.label,
                accessibilityIdentifier: "paneSurfaceToolbar.pullRequest",
                icon: actionSpec.icon,
                tooltip: actionSpec.controlTooltipRenderValue(
                    provenance: .localAction(rawValue: "openPullRequest")
                ),
                isEnabled: isEnabled,
                isSelected: isEnabled,
                selectionEmphasis: isEnabled ? .accent : .standard
            ),
            perform: {
                guard let exactPullRequestURL else { return }
                _ = openExternalURL(exactPullRequestURL)
            }
        )
    }
}
