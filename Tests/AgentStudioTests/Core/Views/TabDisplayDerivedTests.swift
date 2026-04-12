import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct TabDisplayDerivedTests {
    init() {
        installTestAtomScopeIfNeeded()
    }

    @Test
    func placeholderTabName_fallsBackToDerivedWorktreeTitle() {
        withTestAtomStore { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/tab-display-derived"))
            let worktree = Worktree(
                repoId: repo.id,
                name: "feature-name",
                path: URL(filePath: "/tmp/tab-display-derived/feature-name")
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
            atoms.repoCache.setWorktreeEnrichment(
                WorktreeEnrichment(worktreeId: worktree.id, repoId: repo.id, branch: "feature/pane-labels")
            )

            let pane = store.createPane(
                source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
                title: "Ignored",
                facets: PaneContextFacets(
                    repoId: repo.id,
                    repoName: repo.name,
                    worktreeId: worktree.id,
                    worktreeName: worktree.name,
                    cwd: worktree.path
                )
            )
            let tab = Tab(paneId: pane.id, name: "Tab")

            let title = atom(\.tabDisplay).displayTitle(
                for: tab,
                workspacePane: atoms.workspacePane,
                workspaceRepositoryTopology: atoms.workspaceRepositoryTopology,
                repoCache: atoms.repoCache
            )

            #expect(title == "feature-name · feature/pane-labels")
        }
    }

    @Test
    func paneTitle_usesFolderOnlyWhenDetachedHead() {
        withTestAtomStore { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/tab-display-detached"))
            let worktree = Worktree(
                repoId: repo.id,
                name: "feature-name",
                path: URL(filePath: "/tmp/tab-display-detached/feature-name")
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
            let pane = store.createPane(
                source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
                title: "Ignored"
            )

            let title = atom(\.tabDisplay).title(
                for: pane,
                workspaceRepositoryTopology: atoms.workspaceRepositoryTopology,
                repoCache: atoms.repoCache
            )

            #expect(title == "feature-name")
        }
    }
}
