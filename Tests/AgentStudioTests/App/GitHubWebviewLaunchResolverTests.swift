import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
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
        let branchKey = RepoBranchKey(repoId: repo.id, branch: "feature/exact-pr")!
        cache.applyPullRequestFacts([
            branchKey: PullRequestFacts(openCount: 1, exactOpenURL: exactPullRequestURL)
        ])

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
    func resolvesExactPullRequestURLBeforeRepositorySlugEnrichment() throws {
        let store = makeStore()
        let cache = RepoCacheAtom()
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio-no-slug"))
        let worktree = try #require(store.repos.first(where: { $0.id == repo.id })?.worktrees.first)
        let pane = store.createPane(
            launchDirectory: worktree.path,
            title: "Terminal",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        store.appendTab(Tab(paneId: pane.id))
        cache.setRepoEnrichment(.awaitingOrigin(repoId: repo.id))
        cache.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktree.id, repoId: repo.id, branch: "feature/exact-pr")
        )
        let exactPullRequestURL = URL(string: "https://github.com/ShravanSunder/agentstudio/pull/271")!
        let branchKey = RepoBranchKey(repoId: repo.id, branch: "feature/exact-pr")!
        cache.applyPullRequestFacts([
            branchKey: PullRequestFacts(openCount: 1, exactOpenURL: exactPullRequestURL)
        ])

        #expect(GitHubWebviewLaunchResolver.urlForActivePane(store: store, repoCache: cache) == exactPullRequestURL)
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
        let branchKey = RepoBranchKey(repoId: repo.id, branch: "feature/no-url")!
        cache.applyPullRequestFacts([
            branchKey: PullRequestFacts(openCount: 2, exactOpenURL: nil)
        ])

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

    @Test
    func danglingAssociationDoesNotRecoverRepositoryFromCwd() throws {
        let store = makeStore()
        let cache = RepoCacheAtom()
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
        let worktree = try #require(store.repos.first(where: { $0.id == repo.id })?.worktrees.first)
        let pane = Pane(
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: .generateUUIDv7()
                )
            ),
            metadata: PaneMetadata(
                launchDirectory: worktree.path,
                title: "Dangling",
                facets: PaneContextFacets(
                    repoId: UUIDv7.generate(),
                    worktreeId: worktree.id,
                    cwd: worktree.path
                )
            )
        )
        #expect(store.paneAtom.insertRestoredPane(pane))
        store.appendTab(Tab(paneId: pane.id))
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

        #expect(
            GitHubWebviewLaunchResolver.urlForActivePane(store: store, repoCache: cache)
                == URL(string: "https://github.com")
        )
    }
}
