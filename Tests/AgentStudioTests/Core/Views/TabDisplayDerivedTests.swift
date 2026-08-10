import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite(.serialized)
struct TabDisplayDerivedTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test
    func placeholderTabName_fallsBackToDerivedWorktreeTitle() {
        withTestCoreAtoms { atoms in
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
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: repo.worktrees + [worktree])
            guard let storedWorktree = store.repo(repo.id)?.worktrees.first(where: { $0.id == worktree.id }) else {
                Issue.record("Expected linked worktree")
                return
            }
            atoms.repoCache.setWorktreeEnrichment(
                WorktreeEnrichment(
                    worktreeId: storedWorktree.id,
                    repoId: repo.id,
                    branch: "feature/pane-labels"
                )
            )

            let pane = store.createPane(
                launchDirectory: storedWorktree.path,
                title: "Ignored",
                facets: PaneContextFacets(
                    repoId: repo.id,
                    repoName: repo.name,
                    worktreeId: storedWorktree.id,
                    worktreeName: storedWorktree.name,
                    cwd: storedWorktree.path
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
        withTestCoreAtoms { atoms in
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
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: repo.worktrees + [worktree])
            guard let storedWorktree = store.repo(repo.id)?.worktrees.first(where: { $0.id == worktree.id }) else {
                Issue.record("Expected linked worktree")
                return
            }
            let pane = store.createPane(
                launchDirectory: storedWorktree.path,
                title: "Ignored",
                facets: PaneContextFacets(
                    repoId: repo.id,
                    worktreeId: storedWorktree.id,
                    cwd: storedWorktree.path
                ),
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
