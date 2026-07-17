import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("RepositoryTopologyAtom")
struct RepositoryTopologyAtomTests {
    @Test("path lookup resolves current repository metadata without rebuilding structural index")
    func pathLookupResolvesCurrentRepositoryMetadata() throws {
        let atom = RepositoryTopologyAtom()
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-current-metadata")
        let repo = atom.addRepo(at: repoPath)
        let generation = atom.worktreePathIndexGeneration

        atom.setRepoFavorite(repo.id, isFavorite: true)
        atom.updateRepoNote(repo.id, note: "current note")
        try atom.setRepoTags(["current"], repoId: repo.id)

        let match = try #require(atom.repoAndWorktree(containing: repoPath))
        #expect(match.repo.isFavorite)
        #expect(match.repo.note == "current note")
        #expect(match.repo.tags == ["current"])
        #expect(atom.worktreePathIndexGeneration == generation)
    }

    @Test("path lookup resolves current worktree metadata without rebuilding structural index")
    func pathLookupResolvesCurrentWorktreeMetadata() throws {
        let atom = RepositoryTopologyAtom()
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-current-worktree-metadata")
        let repo = atom.addRepo(at: repoPath)
        let worktree = try #require(repo.worktrees.single)
        let generation = atom.worktreePathIndexGeneration

        atom.updateWorktreeNote(worktree.id, note: "worktree note")

        let match = try #require(atom.repoAndWorktree(containing: repoPath))
        #expect(match.worktree.note == "worktree note")
        #expect(atom.worktreePathIndexGeneration == generation)
    }

    @Test("batched topology mutation defers path index rebuild until batch exits")
    func batchedTopologyMutationDefersPathIndexRebuildUntilBatchExits() {
        let atom = RepositoryTopologyAtom()
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

    @Test("repo tags mutate as topology state")
    func repoTagsMutateAsTopologyState() throws {
        let atom = RepositoryTopologyAtom()
        let repo = atom.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-topology-tags"))

        try atom.setRepoTags(["client", "active"], repoId: repo.id)

        #expect(atom.repo(repo.id)?.tags == ["active", "client"])
    }

    @Test("repository tags reject unsafe text")
    func repositoryTagsRejectUnsafeText() throws {
        let atom = RepositoryTopologyAtom()
        let repo = atom.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-topology-invalid-tags"))

        #expect(throws: RepositoryTopologyAtomError.invalidRepositoryTag(" leading")) {
            try atom.setRepoTags([" leading"], repoId: repo.id)
        }
        #expect(throws: RepositoryTopologyAtomError.invalidRepositoryTag("spoof\u{202E}tag")) {
            try atom.setRepoTags(["spoof\u{202E}tag"], repoId: repo.id)
        }
        #expect(throws: RepositoryTopologyAtomError.duplicateRepositoryTag("wip")) {
            try atom.setRepoTags(["wip", "wip"], repoId: repo.id)
        }
    }

    @Test("worktree reconciliation preserves existing notes for matched worktrees")
    func worktreeReconciliationPreservesExistingNotesForMatchedWorktrees() throws {
        let atom = RepositoryTopologyAtom()
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-preserve-notes")
        let repo = atom.addRepo(at: repoPath)
        let mainWorktree = try #require(atom.repo(repo.id)?.worktrees.single)
        atom.updateWorktreeNote(mainWorktree.id, note: "keep this note")

        atom.reconcileDiscoveredWorktrees(
            repo.id,
            worktrees: [
                Worktree(
                    repoId: repo.id,
                    name: "renamed-main",
                    path: repoPath,
                    isMainWorktree: true
                )
            ]
        )

        #expect(atom.worktree(mainWorktree.id)?.note == "keep this note")
    }
}
