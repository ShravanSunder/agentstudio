import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceRepositoryTopologyAtom")
struct WorkspaceRepositoryTopologyAtomTests {
    @Test("ensure main worktree repairs an existing path-matched repo with no worktrees")
    func ensureMainWorktreeRepairsExistingRepoWithoutWorktrees() {
        let atom = WorkspaceRepositoryTopologyAtom()
        let repoPath = URL(filePath: "/tmp/agent-studio-watch-folder")
        let existingRepo = Repo(
            id: UUID(),
            name: "agent-studio-watch-folder",
            repoPath: repoPath,
            worktrees: []
        )
        atom.hydrate(
            runtimeRepos: [existingRepo],
            watchedPaths: [],
            unavailableRepoIds: []
        )

        let worktree = atom.ensureMainWorktree(at: repoPath)

        #expect(worktree.repoId == existingRepo.id)
        #expect(worktree.path == repoPath.standardizedFileURL)
        #expect(worktree.isMainWorktree)
        #expect(atom.repo(existingRepo.id)?.worktrees == [worktree])
        #expect(atom.repoAndWorktree(containing: repoPath)?.worktree.id == worktree.id)
    }

    @Test("batched topology mutation defers path index rebuild until batch exits")
    func batchedTopologyMutationDefersPathIndexRebuildUntilBatchExits() {
        let atom = WorkspaceRepositoryTopologyAtom()
        let startingGeneration = atom.worktreePathIndexGeneration
        let repoAPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-batch-a")
        let repoBPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-batch-b")

        atom.performBatchedTopologyMutation {
            let repoA = atom.addRepo(at: repoAPath)
            _ = atom.addRepo(at: repoBPath)
            atom.reconcileDiscoveredWorktrees(
                repoA.id,
                worktrees: [
                    Worktree(
                        id: repoA.worktrees[0].id,
                        repoId: repoA.id,
                        name: repoAPath.lastPathComponent,
                        path: repoAPath,
                        isMainWorktree: true
                    ),
                    Worktree(
                        repoId: repoA.id,
                        name: "linked",
                        path: repoAPath.deletingLastPathComponent().appending(path: "linked"),
                        isMainWorktree: false
                    ),
                ]
            )

            #expect(atom.worktreePathIndexGeneration == startingGeneration)
        }

        #expect(atom.worktreePathIndexGeneration == startingGeneration + 1)
    }
}
