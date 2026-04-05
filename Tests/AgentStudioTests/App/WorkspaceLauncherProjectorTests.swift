import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct WorkspaceLauncherProjectorTests {
    init() {
        installTestAtomScopeIfNeeded()
    }

    private func makeStore() -> WorkspaceStore {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "workspace-launcher-projector-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
        let atoms = AtomStore()
        let store = WorkspaceStore(
            catalogAtom: atoms.workspaceCatalog,
            graphAtom: atoms.workspaceGraph,
            interactionAtom: atoms.workspaceInteraction,
            persistor: persistor
        )
        store.restore()
        return store
    }

    @Test
    func project_noRepos_returnsFolderIntakeState() {
        withTestAtomStore { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceCatalog,
                graphAtom: atoms.workspaceGraph,
                interactionAtom: atoms.workspaceInteraction
            )
            let result = WorkspaceLauncherProjector.project(store: store)

            #expect(result.kind == .noFolders)
            #expect(result.recentCards.isEmpty)
            #expect(result.showsOpenAll == false)
        }
    }

    @Test
    func project_reposButNoTabs_returnsLauncherStateWithEnrichedCards() {
        withTestAtomStore { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceCatalog,
                graphAtom: atoms.workspaceGraph,
                interactionAtom: atoms.workspaceInteraction
            )
            let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
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
            #expect(result.recentCards[0].statusChips?.branchStatus.prCount == 3)
            #expect(result.recentCards[0].statusChips?.notificationCount == 2)
            #expect(result.showsOpenAll == false)
        }
    }

    @Test
    func project_reposAndTabsPresent_returnsEmptyLauncherModel() {
        withTestAtomStore { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceCatalog,
                graphAtom: atoms.workspaceGraph,
                interactionAtom: atoms.workspaceInteraction
            )
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
            atoms.repoCache.recordRecentTarget(.forWorktree(path: worktree.path, worktree: worktree, repo: repo))

            let result = WorkspaceLauncherProjector.project(store: store)

            #expect(result.kind == .launcher)
            #expect(result.recentCards.isEmpty)
            #expect(result.showsOpenAll == false)
        }
    }

    @Test
    func project_launcherCapsAtSixAndShowsOpenAllForTwoOrMoreTargets() {
        withTestAtomStore { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceCatalog,
                graphAtom: atoms.workspaceGraph,
                interactionAtom: atoms.workspaceInteraction
            )
            _ = store.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))

            for index in 0..<8 {
                atoms.repoCache.recordRecentTarget(
                    .forCwd(URL(fileURLWithPath: "/tmp/project-\(index)"))
                )
            }

            let result = WorkspaceLauncherProjector.project(store: store)

            #expect(result.recentCards.count == 6)
            #expect(result.showsOpenAll == true)
        }
    }
}
