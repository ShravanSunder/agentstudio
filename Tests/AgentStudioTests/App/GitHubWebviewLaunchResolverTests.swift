import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@Suite(.serialized)
@MainActor
struct GitHubWebviewLaunchResolverTests {
    private func makeStore() -> WorkspaceStore {
        let store = WorkspaceStore()
        return store
    }

    @Test
    func resolvesRepoURL_forWorktreeBackedActivePane() throws {
        let store = makeStore()
        let cache = RepoCacheAtom()
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
        guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
            Issue.record("Expected main worktree")
            return
        }

        let pane = store.createPane(
            launchDirectory: worktree.path,
            title: "Terminal",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path),
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        cache.setRepoEnrichment(
            .resolvedRemote(
                repoId: repo.id,
                raw: RawRepoOrigin(origin: "git@github.com:ShravanSunder/agentstudio.git", upstream: nil),
                identity: RepoIdentity(
                    groupKey: "remote:ShravanSunder/agentstudio",
                    remoteSlug: "ShravanSunder/agentstudio",
                    organizationName: "ShravanSunder",
                    displayName: "agentstudio"
                ),
                updatedAt: Date()
            )
        )

        let url = GitHubWebviewLaunchResolver.urlForActivePane(store: store, repoCache: cache)

        #expect(url == URL(string: "https://github.com/ShravanSunder/agentstudio"))
    }

    @Test
    func resolvesExactPullRequestURLWhenBranchFactHasOne() throws {
        let store = makeStore()
        let cache = RepoCacheAtom()
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
        guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
            Issue.record("Expected main worktree")
            return
        }

        let pane = store.createPane(
            launchDirectory: worktree.path,
            title: "Terminal",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path),
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        cache.setRepoEnrichment(
            .resolvedRemote(
                repoId: repo.id,
                raw: RawRepoOrigin(origin: "git@github.com:ShravanSunder/agentstudio.git", upstream: nil),
                identity: RepoIdentity(
                    groupKey: "remote:ShravanSunder/agentstudio",
                    remoteSlug: "ShravanSunder/agentstudio",
                    organizationName: "ShravanSunder",
                    displayName: "agentstudio"
                ),
                updatedAt: Date()
            )
        )
        cache.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: worktree.id,
                repoId: repo.id,
                branch: "feature/exact-pr"
            )
        )
        let exactPullRequestURL = URL(string: "https://github.com/ShravanSunder/agentstudio/pull/264")!
        cache.applyPullRequestFacts(
            repoId: repo.id,
            factsByBranch: [
                "feature/exact-pr": PullRequestFacts(openCount: 1, exactOpenURL: exactPullRequestURL)
            ]
        )

        let url = GitHubWebviewLaunchResolver.urlForActivePane(store: store, repoCache: cache)

        #expect(url == exactPullRequestURL)
        #expect(
            GitHubWebviewLaunchResolver.pullRequestsURL(
                for: pane.id,
                store: store,
                repoCache: cache
            ) == exactPullRequestURL
        )
    }

    @Test
    func pullRequestURLIsUnavailableWhenBranchFactHasNoExactURL() throws {
        let store = makeStore()
        let cache = RepoCacheAtom()
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
        let worktree = try #require(store.repos.first(where: { $0.id == repo.id })?.worktrees.first)
        let pane = store.createPane(
            launchDirectory: worktree.path,
            title: "Terminal",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        cache.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktree.id, repoId: repo.id, branch: "feature/no-url")
        )
        cache.applyPullRequestFacts(
            repoId: repo.id,
            factsByBranch: ["feature/no-url": PullRequestFacts(openCount: 2, exactOpenURL: nil)]
        )

        #expect(
            GitHubWebviewLaunchResolver.pullRequestsURL(
                for: pane.id,
                store: store,
                repoCache: cache
            ) == nil
        )
    }

    @Test
    func resolvesRepoURL_forFloatingCwdMappedBackToRepo() {
        let store = makeStore()
        let cache = RepoCacheAtom()
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
        let cwd = URL(fileURLWithPath: "/tmp/agent-studio/Sources")
        let pane = store.createPane(
            launchDirectory: cwd,
            title: "Floating"
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        cache.setRepoEnrichment(
            .resolvedRemote(
                repoId: repo.id,
                raw: RawRepoOrigin(origin: "git@github.com:ShravanSunder/agentstudio.git", upstream: nil),
                identity: RepoIdentity(
                    groupKey: "remote:ShravanSunder/agentstudio",
                    remoteSlug: "ShravanSunder/agentstudio",
                    organizationName: "ShravanSunder",
                    displayName: "agentstudio"
                ),
                updatedAt: Date()
            )
        )

        let url = GitHubWebviewLaunchResolver.urlForActivePane(store: store, repoCache: cache)

        #expect(url == URL(string: "https://github.com/ShravanSunder/agentstudio"))
    }

    @Test
    func fallsBackToGitHubHome_whenNoRepoSlugIsAvailable() {
        let store = makeStore()
        let cache = RepoCacheAtom()

        let url = GitHubWebviewLaunchResolver.urlForActivePane(store: store, repoCache: cache)

        #expect(url == URL(string: "https://github.com"))
    }

    @Test
    func resolvesRepoURL_forSpecificPaneId() {
        let store = makeStore()
        let cache = RepoCacheAtom()
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
        guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
            Issue.record("Expected main worktree")
            return
        }

        let pane = store.createPane(
            launchDirectory: worktree.path,
            title: "Terminal",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path),
        )
        cache.setRepoEnrichment(
            .resolvedRemote(
                repoId: repo.id,
                raw: RawRepoOrigin(origin: "git@github.com:ShravanSunder/agentstudio.git", upstream: nil),
                identity: RepoIdentity(
                    groupKey: "remote:ShravanSunder/agentstudio",
                    remoteSlug: "ShravanSunder/agentstudio",
                    organizationName: "ShravanSunder",
                    displayName: "agentstudio"
                ),
                updatedAt: Date()
            )
        )

        let url = GitHubWebviewLaunchResolver.url(
            for: pane.id,
            store: store,
            repoCache: cache
        )

        #expect(url == URL(string: "https://github.com/ShravanSunder/agentstudio"))
    }
}
