import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct GitHubWebviewLaunchResolverTests {
    private func makeStore() -> WorkspaceStore {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "github-webview-launch-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        let store = WorkspaceStore(persistor: persistor)
        store.restore()
        return store
    }

    @Test
    func resolvesRepoURL_forWorktreeBackedActivePane() throws {
        let store = makeStore()
        let cache = WorkspaceRepoCache()
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
        guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
            Issue.record("Expected main worktree")
            return
        }

        let pane = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Terminal"
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
    func resolvesPullListURL_whenPullRequestSignalExists() throws {
        let store = makeStore()
        let cache = WorkspaceRepoCache()
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
        guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
            Issue.record("Expected main worktree")
            return
        }

        let pane = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Terminal"
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
        cache.setPullRequestCount(4, for: worktree.id)

        let url = GitHubWebviewLaunchResolver.urlForActivePane(store: store, repoCache: cache)

        #expect(url == URL(string: "https://github.com/ShravanSunder/agentstudio/pulls"))
    }

    @Test
    func resolvesRepoURL_forFloatingCwdMappedBackToRepo() {
        let store = makeStore()
        let cache = WorkspaceRepoCache()
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
        let cwd = URL(fileURLWithPath: "/tmp/agent-studio/Sources")
        let pane = store.createPane(
            source: .floating(launchDirectory: cwd, title: "Floating"),
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
        let cache = WorkspaceRepoCache()

        let url = GitHubWebviewLaunchResolver.urlForActivePane(store: store, repoCache: cache)

        #expect(url == URL(string: "https://github.com"))
    }

    @Test
    func resolvesRepoURL_forSpecificPaneId() {
        let store = makeStore()
        let cache = WorkspaceRepoCache()
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
        guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
            Issue.record("Expected main worktree")
            return
        }

        let pane = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Terminal"
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
