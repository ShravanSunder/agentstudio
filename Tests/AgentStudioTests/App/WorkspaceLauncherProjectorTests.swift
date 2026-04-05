import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct WorkspaceLauncherProjectorTests {
    private func makeStore() -> WorkspaceStore {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "workspace-launcher-projector-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        let store = WorkspaceStore(persistor: persistor)
        store.restore()
        return store
    }

    @Test
    func project_noRepos_returnsFolderIntakeState() {
        let store = makeStore()
        let cache = WorkspaceRepoCache()

        let result = WorkspaceLauncherProjector.project(
            store: store,
            repoCache: cache
        )

        #expect(result.kind == .noFolders)
        #expect(result.recentCards.isEmpty)
        #expect(result.showsOpenAll == false)
    }

    @Test
    func project_reposButNoTabs_returnsLauncherStateWithEnrichedCards() {
        let store = makeStore()
        let cache = WorkspaceRepoCache()
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
        guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
            Issue.record("Expected main worktree")
            return
        }

        cache.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: worktree.id,
                repoId: repo.id,
                branch: "main"
            )
        )
        cache.setPullRequestCount(3, for: worktree.id)
        cache.setNotificationCount(2, for: worktree.id)
        cache.recordRecentTarget(.forWorktree(path: worktree.path, worktree: worktree, repo: repo))

        let result = WorkspaceLauncherProjector.project(
            store: store,
            repoCache: cache
        )

        #expect(result.kind == .launcher)
        #expect(result.recentCards.count == 1)
        #expect(result.recentCards[0].title == worktree.name)
        #expect(result.recentCards[0].detail == "main")
        #expect(result.recentCards[0].checkoutIconKind == .mainCheckout)
        #expect(result.recentCards[0].iconColorHex == SidebarRepoGrouping.automaticPaletteHexes[0])
        #expect(result.recentCards[0].statusChips?.branchStatus.prCount == 3)
        #expect(result.recentCards[0].statusChips?.notificationCount == 2)
        #expect(result.showsOpenAll == false)
    }

    @Test
    func project_reposAndTabsPresent_returnsEmptyLauncherModel() {
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
        store.appendTab(Tab(paneId: pane.id))
        cache.recordRecentTarget(.forWorktree(path: worktree.path, worktree: worktree, repo: repo))

        let result = WorkspaceLauncherProjector.project(
            store: store,
            repoCache: cache
        )

        #expect(result.kind == .launcher)
        #expect(result.recentCards.isEmpty)
        #expect(result.showsOpenAll == false)
    }

    @Test
    func project_launcherCapsAtFifteenAndShowsOpenAllForTwoOrMoreTargets() {
        let store = makeStore()
        let cache = WorkspaceRepoCache()
        let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
        guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
            Issue.record("Expected main worktree")
            return
        }

        for index in 0..<20 {
            cache.recordRecentTarget(
                .forWorktree(
                    path: worktree.path.appending(path: "nested-\(index)"),
                    worktree: worktree,
                    repo: repo
                )
            )
        }

        let result = WorkspaceLauncherProjector.project(
            store: store,
            repoCache: cache
        )

        #expect(result.recentCards.count == 15)
        #expect(result.showsOpenAll == true)
    }

    @Test
    func project_unresolvedRecentTarget_isDroppedFromLauncherCards() {
        let store = makeStore()
        let cache = WorkspaceRepoCache()
        _ = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))

        cache.recordRecentTarget(.forCwd(URL(fileURLWithPath: "/tmp/missing-project")))

        let result = WorkspaceLauncherProjector.project(
            store: store,
            repoCache: cache
        )

        #expect(result.kind == .launcher)
        #expect(result.recentCards.isEmpty)
        #expect(result.showsOpenAll == false)
    }
}
