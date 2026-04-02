import Foundation
import os

@MainActor
enum GitHubWebviewLaunchResolver {
    private static let fallbackURL = URL(string: "https://github.com")!
    private static let logger = Logger(subsystem: "com.agentstudio", category: "GitHubWebviewLaunchResolver")

    static func urlForActivePane(
        store: WorkspaceStore,
        repoCache: WorkspaceRepoCache
    ) -> URL {
        guard
            let activeTabId = store.activeTabId,
            let activePaneId = store.tab(activeTabId)?.activePaneId,
            let pane = store.pane(activePaneId)
        else {
            logger.debug("Falling back to GitHub home because there is no active pane")
            return fallbackURL
        }

        guard let repo = repoForPane(pane, store: store) else {
            logger.debug("Falling back to GitHub home because no repo resolved for active pane")
            return fallbackURL
        }

        guard let slug = repoCache.repoEnrichmentByRepoId[repo.id]?.remoteSlug else {
            logger.info(
                "Falling back to GitHub home because repo slug is unavailable for repoId=\(repo.id.uuidString, privacy: .public)"
            )
            return fallbackURL
        }

        guard let url = URL(string: "https://github.com/\(slug)") else {
            logger.error("Failed to build GitHub URL for slug=\(slug, privacy: .public)")
            return fallbackURL
        }

        return url
    }

    private static func repoForPane(_ pane: Pane, store: WorkspaceStore) -> Repo? {
        if let repoId = pane.repoId,
            let repo = store.repo(repoId)
        {
            return repo
        }

        return store.repoAndWorktree(containing: pane.metadata.facets.cwd)?.repo
    }
}
