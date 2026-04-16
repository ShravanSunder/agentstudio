import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct WorkspaceLauncherProjectorTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private func makeStore() -> WorkspaceStore {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "workspace-launcher-projector-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        atom(\.repoCache).clear()
        let atoms = AtomRegistry()
        let store = WorkspaceStore(
            metadataAtom: atoms.workspaceMetadata,
            repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
            paneAtom: atoms.workspacePane,
            tabLayoutAtom: atoms.workspaceTabLayout,
            mutationCoordinator: atoms.workspaceMutationCoordinator,
            persistor: persistor
        )
        store.restore()
        return store
    }

    @Test
    func project_noRepos_returnsFolderIntakeState() {
        withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                metadataAtom: atoms.workspaceMetadata,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
                paneAtom: atoms.workspacePane,
                tabLayoutAtom: atoms.workspaceTabLayout,
                mutationCoordinator: atoms.workspaceMutationCoordinator
            )
            let result = WorkspaceLauncherProjector.project(store: store)

            #expect(result.kind == .noFolders)
            #expect(result.recentCards.isEmpty)
            #expect(result.showsOpenAll == false)
        }
    }

    @Test
    func project_scanningWithoutRepos_returnsScanningState() {
        let store = makeStore()
        store.beginFolderScan(URL(fileURLWithPath: "/tmp/scanning-root"))

        let result = WorkspaceLauncherProjector.project(store: store)

        #expect(result.kind == .scanning(URL(fileURLWithPath: "/tmp/scanning-root")))
        #expect(result.recentCards.isEmpty)
    }

    @Test
    func project_emptyFolderScanWithoutRepos_returnsEmptyScanState() {
        let store = makeStore()
        store.completeFolderScan(
            rootPath: URL(fileURLWithPath: "/tmp/empty-root"),
            discoveredRepoCount: 0
        )

        let result = WorkspaceLauncherProjector.project(store: store)

        #expect(result.kind == .scanEmpty(URL(fileURLWithPath: "/tmp/empty-root")))
        #expect(result.recentCards.isEmpty)
        #expect(result.showsOpenAll == false)
    }

    @Test
    func project_emptyFolderScanWithRepos_returnsLauncherState() {
        let store = makeStore()
        _ = store.repositoryTopologyAtom.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
        store.completeFolderScan(
            rootPath: URL(fileURLWithPath: "/tmp/empty-root"),
            discoveredRepoCount: 0
        )

        let result = WorkspaceLauncherProjector.project(store: store)

        #expect(result.kind == .launcher)
    }

    @Test
    func project_reposButNoTabs_returnsLauncherStateWithEnrichedCards() {
        withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                metadataAtom: atoms.workspaceMetadata,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
                paneAtom: atoms.workspacePane,
                tabLayoutAtom: atoms.workspaceTabLayout,
                mutationCoordinator: atoms.workspaceMutationCoordinator
            )
            let repo = store.repositoryTopologyAtom.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
            guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
                Issue.record("Expected main worktree")
                return
            }

            atoms.repoCache.setWorktreeEnrichment(
                WorktreeEnrichment(
                    worktreeId: worktree.id,
                    repoId: repo.id,
                    branch: "main"
                )
            )
            atoms.repoCache.setPullRequestCount(3, for: worktree.id)
            atoms.repoCache.setNotificationCount(2, for: worktree.id)
            atoms.repoCache.recordRecentTarget(.forWorktree(path: worktree.path, worktree: worktree, repo: repo))

            let result = WorkspaceLauncherProjector.project(store: store)

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
    }

    @Test
    func project_reposAndTabsPresent_returnsEmptyLauncherModel() {
        withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                metadataAtom: atoms.workspaceMetadata,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
                paneAtom: atoms.workspacePane,
                tabLayoutAtom: atoms.workspaceTabLayout,
                mutationCoordinator: atoms.workspaceMutationCoordinator
            )
            let repo = store.repositoryTopologyAtom.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
            guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
                Issue.record("Expected main worktree")
                return
            }

            let pane = store.paneAtom.createPane(
                source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
                title: "Terminal"
            )
            store.tabLayoutAtom.appendTab(Tab(paneId: pane.id))
            atoms.repoCache.recordRecentTarget(.forWorktree(path: worktree.path, worktree: worktree, repo: repo))

            let result = WorkspaceLauncherProjector.project(store: store)

            #expect(result.kind == .launcher)
            #expect(result.recentCards.isEmpty)
            #expect(result.showsOpenAll == false)
        }
    }

    @Test
    func project_launcherCapsAtFifteenAndShowsOpenAllForTwoOrMoreTargets() {
        let store = makeStore()
        let repo = store.repositoryTopologyAtom.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
        guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
            Issue.record("Expected main worktree")
            return
        }

        let cache = atom(\.repoCache)
        for index in 0..<20 {
            cache.recordRecentTarget(
                .forCwd(
                    worktree.path.appending(path: "nested-\(index)"),
                    title: "nested-\(index)",
                    subtitle: repo.name
                )
            )
        }

        let result = WorkspaceLauncherProjector.project(store: store)

        #expect(result.recentCards.count == 15)
        #expect(result.showsOpenAll == true)
    }

    @Test
    func project_unresolvedRecentTarget_isDroppedFromLauncherCards() {
        let store = makeStore()
        _ = store.repositoryTopologyAtom.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))

        let cache = atom(\.repoCache)
        cache.recordRecentTarget(.forCwd(URL(fileURLWithPath: "/tmp/missing-project")))

        let result = WorkspaceLauncherProjector.project(store: store)

        #expect(result.kind == .launcher)
        #expect(result.recentCards.isEmpty)
        #expect(result.showsOpenAll == false)
    }
}
