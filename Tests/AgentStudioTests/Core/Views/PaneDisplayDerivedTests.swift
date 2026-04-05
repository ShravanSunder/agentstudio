import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneDisplayDerivedTests {
    init() {
        installTestAtomScopeIfNeeded()
    }

    @Test
    func worktreeBackedPane_usesRepoBranchAndFolderLabel() {
        withTestAtomStore { atoms in
            let store = WorkspaceStore(atom: atoms.workspace)
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
        withTestAtomStore { atoms in
            let store = WorkspaceStore(atom: atoms.workspace)
            let pane = store.createPane(
                source: .floating(launchDirectory: URL(fileURLWithPath: "/tmp/project-dev"), title: "ignored"),
                title: "ignored",
                facets: PaneContextFacets(cwd: URL(fileURLWithPath: "/tmp/project-dev"))
            )

            let parts = atom(\.paneDisplay).displayParts(for: pane)

            #expect(parts.primaryLabel == "project-dev")
        }
    }
}
