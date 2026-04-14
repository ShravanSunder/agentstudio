import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneDisplayDerivedTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test
    func worktreeBackedPane_usesRepoBranchAndFolderLabel() {
        withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/agent-studio"))
            let worktree = makeWorktree(
                repoId: repo.id,
                name: "feature-name",
                path: "/tmp/agent-studio/feature-name"
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
            atoms.repoCache.setWorktreeEnrichment(
                WorktreeEnrichment(worktreeId: worktree.id, repoId: repo.id, branch: "feature/pane-labels")
            )

            let pane = store.createPane(
                source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
                title: "Ignored Terminal Title",
                facets: PaneContextFacets(
                    repoId: repo.id,
                    repoName: "agent-studio",
                    worktreeId: worktree.id,
                    worktreeName: "feature-name",
                    cwd: URL(fileURLWithPath: "/tmp/agent-studio/feature-name/src")
                )
            )

            let parts = atom(\.paneDisplay).displayParts(for: pane)

            #expect(parts.primaryLabel == "agent-studio | feature/pane-labels | feature-name")
        }
    }

    @Test
    func floatingPane_usesCwdFolderFallback() {
        withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let pane = store.createPane(
                source: .floating(launchDirectory: URL(fileURLWithPath: "/tmp/project-dev"), title: "ignored"),
                title: "ignored",
                facets: PaneContextFacets(cwd: URL(fileURLWithPath: "/tmp/project-dev"))
            )

            let parts = atom(\.paneDisplay).displayParts(for: pane)

            #expect(parts.primaryLabel == "project-dev")
        }
    }

    @Test
    func accentColorHex_returnsStablePaletteEntry_forRepoBackedPane() {
        withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/agent-studio-colors"))
            let worktree = makeWorktree(
                repoId: repo.id,
                name: "main",
                path: "/tmp/agent-studio-colors/main"
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
            let pane = store.createPane(
                source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
                title: "Color"
            )

            let first = atom(\.paneDisplay).accentColorHex(for: pane.id)
            let second = atom(\.paneDisplay).accentColorHex(for: pane.id)

            #expect(first == second)
            #expect(first != nil)
            #expect(AppStyle.accentPaletteHexes.contains(first!))
        }
    }

    @Test
    func accentColorHex_returnsNil_forPaneWithoutRepo() {
        withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let pane = store.createPane(source: .floating(launchDirectory: nil, title: nil))

            #expect(atom(\.paneDisplay).accentColorHex(for: pane.id) == nil)
        }
    }
}
