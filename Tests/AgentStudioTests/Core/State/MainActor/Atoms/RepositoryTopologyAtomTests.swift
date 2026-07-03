import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("RepositoryTopologyAtom")
struct RepositoryTopologyAtomTests {
    @Test("ensure main worktree repairs an existing path-matched repo with no worktrees")
    func ensureMainWorktreeRepairsExistingRepoWithoutWorktrees() {
        let atom = RepositoryTopologyAtom()
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

    @Test("repo and worktree tags mutate as topology state")
    func repoAndWorktreeTagsMutateAsTopologyState() throws {
        let atom = RepositoryTopologyAtom()
        let repo = atom.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-topology-tags"))
        let worktree = try #require(atom.repo(repo.id)?.worktrees.single)

        try atom.setRepoTags(["client", "active"], repoId: repo.id)
        try atom.setWorktreeTags(["wip", "review"], worktreeId: worktree.id)

        #expect(atom.repo(repo.id)?.tags == ["active", "client"])
        #expect(atom.worktree(worktree.id)?.tags == ["review", "wip"])
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

    @Test("worktree reconciliation preserves existing tags for matched worktrees")
    func worktreeReconciliationPreservesExistingTagsForMatchedWorktrees() throws {
        let atom = RepositoryTopologyAtom()
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-preserve-tags")
        let repo = atom.addRepo(at: repoPath)
        let mainWorktree = try #require(atom.repo(repo.id)?.worktrees.single)
        try atom.setWorktreeTags(["keep"], worktreeId: mainWorktree.id)

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

        #expect(atom.worktree(mainWorktree.id)?.tags == ["keep"])
    }
}
