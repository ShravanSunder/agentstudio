import AgentStudioCore
import Foundation
import os

@MainActor
enum GitHubWebviewLaunchResolver {
    private static let fallbackURL = URL(string: "https://github.com")!
    private static let logger = Logger(subsystem: "com.agentstudio", category: "GitHubWebviewLaunchResolver")

    static func url(
        for paneId: UUID,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom
    ) -> URL {
        guard let pane = store.paneAtom.pane(paneId) else {
            logger.debug("Falling back to GitHub home because paneId=\(paneId.uuidString, privacy: .public) is missing")
            return fallbackURL
        }

        return url(for: pane, store: store, repoCache: repoCache)
    }

    static func urlForActivePane(
        store: WorkspaceStore,
        repoCache: RepoCacheAtom
    ) -> URL {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        guard
            let activeTabId = store.tabShellAtom.activeTabId,
            let activePaneId = workspaceTab.tab(activeTabId)?.activePaneId
        else {
            logger.debug("Falling back to GitHub home because there is no active pane")
            return fallbackURL
        }

        return url(for: activePaneId, store: store, repoCache: repoCache)
    }

    static func pullRequestsURL(
        for paneId: UUID,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom
    ) -> URL? {
        guard
            let pane = store.paneAtom.pane(paneId),
            let context = repoContext(for: pane, store: store),
            let exactOpenURL = pullRequestFacts(for: context, repoCache: repoCache)?.exactOpenURL
        else {
            return nil
        }

        return exactOpenURL
    }

    static func hasResolvableWorktreeContext(
        for paneId: UUID,
        store: WorkspaceStore
    ) -> Bool {
        guard let pane = store.paneAtom.pane(paneId),
            let context = repoContext(for: pane, store: store)
        else { return false }
        return context.worktreeId != nil
    }

    private static func url(
        for pane: Pane,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom
    ) -> URL {
        guard let context = repoContext(for: pane, store: store) else {
            logger.debug("Falling back to GitHub home because no repo resolved for active pane")
            return fallbackURL
        }

        if let exactOpenURL = pullRequestFacts(for: context, repoCache: repoCache)?.exactOpenURL {
            return exactOpenURL
        }

        guard let slug = repoCache.repoEnrichment(for: context.repo.id)?.remoteSlug else {
            logger.info(
                "Falling back to GitHub home because repo slug is unavailable for repoId=\(context.repo.id.uuidString, privacy: .public)"
            )
            return fallbackURL
        }

        let path = "/\(slug)"

        guard let url = githubURL(path: path) else {
            logger.error("Failed to build GitHub URL for path=\(path, privacy: .public)")
            return fallbackURL
        }

        return url
    }

    private static func githubURL(path: String) -> URL? {
        var components = URLComponents(url: fallbackURL, resolvingAgainstBaseURL: false)
        components?.path = path
        return components?.url
    }

    private static func repoContext(
        for pane: Pane,
        store: WorkspaceStore
    ) -> (repo: Repo, worktreeId: UUID?)? {
        let workspaceRepositoryTopology = store.repositoryTopologyAtom
        if let repoId = pane.repoId,
            let repo = workspaceRepositoryTopology.repo(repoId)
        {
            return (repo, pane.worktreeId)
        }

        guard let resolved = workspaceRepositoryTopology.repoAndWorktree(containing: pane.metadata.facets.cwd) else {
            return nil
        }
        return (resolved.repo, resolved.worktree.id)
    }

    private static func pullRequestFacts(
        for context: (repo: Repo, worktreeId: UUID?),
        repoCache: RepoCacheAtom
    ) -> PullRequestFacts? {
        guard
            let worktreeId = context.worktreeId,
            let enrichment = repoCache.worktreeEnrichment(for: worktreeId),
            let key = RepoBranchKey(repoId: context.repo.id, branch: enrichment.branch)
        else {
            return nil
        }
        return repoCache.pullRequestFacts(for: key)
    }
}
