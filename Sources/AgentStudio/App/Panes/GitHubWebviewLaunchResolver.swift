import Foundation
import os

@MainActor
enum GitHubWebviewLaunchResolver {
    private static let fallbackURL = URL(string: "https://github.com")!
    private static let logger = Logger(subsystem: "com.agentstudio", category: "GitHubWebviewLaunchResolver")

    static func url(
        for paneId: UUID,
        store: WorkspaceStore,
        repoCache: WorkspaceRepoCache
    ) -> URL {
        guard let pane = store.pane(paneId) else {
            logger.debug("Falling back to GitHub home because paneId=\(paneId.uuidString, privacy: .public) is missing")
            return fallbackURL
        }

        return url(for: pane, store: store, repoCache: repoCache)
    }

    static func urlForActivePane(
        store: WorkspaceStore,
        repoCache: WorkspaceRepoCache
    ) -> URL {
        guard
            let activeTabId = store.activeTabId,
            let activePaneId = store.tab(activeTabId)?.activePaneId
        else {
            logger.debug("Falling back to GitHub home because there is no active pane")
            return fallbackURL
        }

        return url(for: activePaneId, store: store, repoCache: repoCache)
    }

    private static func url(
        for pane: Pane,
        store: WorkspaceStore,
        repoCache: WorkspaceRepoCache
    ) -> URL {
        guard let context = repoContext(for: pane, store: store) else {
            logger.debug("Falling back to GitHub home because no repo resolved for active pane")
            return fallbackURL
        }

        guard let slug = repoCache.repoEnrichmentByRepoId[context.repo.id]?.remoteSlug else {
            logger.info(
                "Falling back to GitHub home because repo slug is unavailable for repoId=\(context.repo.id.uuidString, privacy: .public)"
            )
            return fallbackURL
        }

        let path =
            if let worktreeId = context.worktreeId,
                repoCache.pullRequestCountByWorktreeId[worktreeId, default: 0] > 0
            {
                "/\(slug)/pulls"
            } else {
                "/\(slug)"
            }

        var components = URLComponents(url: fallbackURL, resolvingAgainstBaseURL: false)
        components?.path = path

        guard let url = components?.url else {
            logger.error("Failed to build GitHub URL for path=\(path, privacy: .public)")
            return fallbackURL
        }

        return url
    }

    private static func repoContext(
        for pane: Pane,
        store: WorkspaceStore
    ) -> (repo: Repo, worktreeId: UUID?)? {
        if let repoId = pane.repoId,
            let repo = store.repo(repoId)
        {
            return (repo, pane.worktreeId)
        }

        guard let resolved = store.repoAndWorktree(containing: pane.metadata.facets.cwd) else {
            return nil
        }
        return (resolved.repo, resolved.worktree.id)
    }
}
