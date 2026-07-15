import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("RepositoryTopologyAtom")
struct RepositoryTopologyAtomTests {
    enum ExistingIdentityMatchKind: Sendable {
        case path
        case mainWorktree
        case name
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

    @Test("worktree reconciliation consumes an existing identity only once")
    func worktreeReconciliationConsumesExistingIdentityOnlyOnce() throws {
        let atom = RepositoryTopologyAtom()
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-existing-identity")
        let renamedPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-renamed/existing-identity")
        let repo = atom.addRepo(at: repoPath)
        let existingMainWorktree = try #require(atom.repo(repo.id)?.worktrees.single)
        try atom.setWorktreeTags(["keep"], worktreeId: existingMainWorktree.id)

        atom.reconcileDiscoveredWorktrees(
            repo.id,
            worktrees: [
                Worktree(
                    repoId: repo.id,
                    name: repoPath.lastPathComponent,
                    path: repoPath,
                    isMainWorktree: true
                ),
                Worktree(
                    repoId: repo.id,
                    name: repoPath.lastPathComponent,
                    path: renamedPath,
                    isMainWorktree: false
                ),
            ]
        )

        let reconciledWorktrees = try #require(atom.repo(repo.id)?.worktrees)
        #expect(reconciledWorktrees.count == 2)
        #expect(Set(reconciledWorktrees.map(\.id)).count == 2)
        #expect(reconciledWorktrees[0].id == existingMainWorktree.id)
        #expect(reconciledWorktrees[0].tags == ["keep"])
        #expect(reconciledWorktrees[1].id != existingMainWorktree.id)
    }

    @Test("scanned reconciliation mints UUIDv7 identities and reports an exact delta")
    func scannedReconciliationMintsUUIDv7IdentitiesAndReportsExactDelta() throws {
        let atom = RepositoryTopologyAtom()
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-scanned")
        let linkedPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-linked/scanned")
        let repo = atom.addRepo(at: repoPath)
        let existingMainWorktree = try #require(atom.repo(repo.id)?.worktrees.single)
        let traceId = UUIDv7.generate()

        let result = atom.reconcileScannedWorktrees(
            repo.id,
            scannedWorktrees: RepositoryScannedWorktrees(
                main: RepositoryScannedMainWorktree(
                    name: repoPath.lastPathComponent,
                    path: repoPath
                ),
                linked: [
                    RepositoryScannedLinkedWorktree(
                        name: repoPath.lastPathComponent,
                        path: linkedPath
                    )
                ]
            ),
            traceId: traceId
        )

        guard case .accepted(let acceptance) = result else {
            Issue.record("expected scanned reconciliation acceptance")
            return
        }
        let reconciledWorktrees = try #require(atom.repo(repo.id)?.worktrees)
        #expect(reconciledWorktrees.count == 2)
        #expect(Set(reconciledWorktrees.map(\.id)).count == 2)
        #expect(reconciledWorktrees[0].id == existingMainWorktree.id)
        #expect(UUIDv7.isV7(reconciledWorktrees[1].id))
        #expect(acceptance.delta.preservedWorktreeIds == [existingMainWorktree.id])
        #expect(acceptance.delta.addedWorktreeIds == [reconciledWorktrees[1].id])
        #expect(acceptance.delta.removedWorktrees.isEmpty)
        #expect(acceptance.delta.didChange)
        #expect(acceptance.delta.traceId == traceId)
    }

    @Test("reconciliation rejection preserves exact topology and path index generation")
    func reconciliationRejectionPreservesExactTopologyAndPathIndexGeneration() throws {
        let atom = RepositoryTopologyAtom()
        let firstRepo = atom.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-topology-first"))
        let secondRepo = atom.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-topology-second"))
        let stateBeforeRejection = atom.repos
        let generationBeforeRejection = atom.worktreePathIndexGeneration
        let conflictingWorktreeId = UUIDv7.generate()

        let result = atom.reconcileDiscoveredWorktrees(
            firstRepo.id,
            worktrees: [
                Worktree(
                    id: conflictingWorktreeId,
                    repoId: firstRepo.id,
                    name: "conflict",
                    path: secondRepo.repoPath,
                    isMainWorktree: false
                )
            ]
        )

        #expect(
            result
                == .rejected(
                    .duplicateWorktreeStableKey(
                        StableKey.fromPath(secondRepo.repoPath)
                    )
                )
        )
        #expect(atom.repos == stateBeforeRejection)
        #expect(atom.worktreePathIndexGeneration == generationBeforeRejection)
    }

    @Test("repo reassociation rejection preserves topology, availability, and path index generation")
    func repoReassociationRejectionPreservesAllTopologyState() {
        let atom = RepositoryTopologyAtom()
        let firstRepo = atom.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-reassociation-first"))
        let secondRepo = atom.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-reassociation-second"))
        atom.markRepoUnavailable(firstRepo.id)
        let reposBeforeRejection = atom.repos
        let unavailableRepoIdsBeforeRejection = atom.unavailableRepoIds
        let generationBeforeRejection = atom.worktreePathIndexGeneration

        let result = atom.reassociateRepo(
            firstRepo.id,
            to: URL(fileURLWithPath: "/tmp/agentstudio-reassociation-relocated"),
            discoveredWorktrees: [
                Worktree(
                    repoId: firstRepo.id,
                    name: "conflicting-linked-worktree",
                    path: secondRepo.repoPath,
                    isMainWorktree: false
                )
            ]
        )

        #expect(
            result
                == .rejected(
                    .worktreeReconciliation(
                        .duplicateWorktreeStableKey(StableKey.fromPath(secondRepo.repoPath))
                    )
                )
        )
        #expect(atom.repos == reposBeforeRejection)
        #expect(atom.unavailableRepoIds == unavailableRepoIdsBeforeRejection)
        #expect(atom.worktreePathIndexGeneration == generationBeforeRejection)
    }

    @Test("repo reassociation atomically applies topology with one path index generation")
    func repoReassociationAppliesTopologyWithOnePathIndexGeneration() throws {
        let atom = RepositoryTopologyAtom()
        let oldPath = URL(fileURLWithPath: "/tmp/agentstudio-reassociation-old")
        let relocatedPath = URL(fileURLWithPath: "/tmp/agentstudio-reassociation-new")
        let repo = atom.addRepo(at: oldPath)
        let existingWorktree = try #require(atom.repo(repo.id)?.worktrees.single)
        atom.markRepoUnavailable(repo.id)
        let generationBeforeReassociation = atom.worktreePathIndexGeneration

        let result = atom.reassociateRepo(
            repo.id,
            to: relocatedPath,
            discoveredWorktrees: [
                Worktree(
                    repoId: repo.id,
                    name: "relocated-main",
                    path: relocatedPath,
                    isMainWorktree: true
                )
            ]
        )

        guard case .accepted(let acceptance) = result else {
            Issue.record("expected repo reassociation acceptance")
            return
        }
        let reassociatedRepo = try #require(atom.repo(repo.id))
        let reassociatedWorktree = try #require(reassociatedRepo.worktrees.single)
        #expect(reassociatedRepo.name == relocatedPath.lastPathComponent)
        #expect(reassociatedRepo.repoPath == relocatedPath)
        #expect(reassociatedWorktree.id == existingWorktree.id)
        #expect(reassociatedWorktree.name == "relocated-main")
        #expect(reassociatedWorktree.path == relocatedPath)
        #expect(atom.isRepoUnavailable(repo.id) == false)
        #expect(atom.worktreePathIndexGeneration == generationBeforeReassociation + 1)
        #expect(acceptance.worktreeIds == [existingWorktree.id])
        #expect(acceptance.delta.preservedWorktreeIds == [existingWorktree.id])
        #expect(acceptance.delta.addedWorktreeIds.isEmpty)
        #expect(acceptance.delta.removedWorktrees.isEmpty)
        #expect(acceptance.delta.didChange)
    }

    @Test("repo reassociation rejects another repository stable key without worktree candidates")
    func repoReassociationRejectsDuplicateRepositoryStableKey() {
        let atom = RepositoryTopologyAtom()
        let firstRepo = atom.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-reassociation-key-first"))
        let secondRepo = atom.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-reassociation-key-second"))
        atom.markRepoUnavailable(firstRepo.id)
        let reposBeforeRejection = atom.repos
        let unavailableRepoIdsBeforeRejection = atom.unavailableRepoIds
        let generationBeforeRejection = atom.worktreePathIndexGeneration

        let result = atom.reassociateRepo(
            firstRepo.id,
            to: secondRepo.repoPath,
            discoveredWorktrees: []
        )

        #expect(
            result
                == .rejected(
                    .duplicateRepositoryStableKey(StableKey.fromPath(secondRepo.repoPath))
                )
        )
        #expect(atom.repos == reposBeforeRejection)
        #expect(atom.unavailableRepoIds == unavailableRepoIdsBeforeRejection)
        #expect(atom.worktreePathIndexGeneration == generationBeforeRejection)
    }

    @Test("explicit identified reconciliation removes every existing worktree")
    func explicitIdentifiedReconciliationRemovesEveryExistingWorktree() throws {
        let atom = RepositoryTopologyAtom()
        let repo = atom.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-topology-empty"))
        let existingWorktree = try #require(atom.repo(repo.id)?.worktrees.single)

        let result = atom.reconcileDiscoveredWorktrees(
            repo.id,
            worktrees: []
        )

        guard case .accepted(let acceptance) = result else {
            Issue.record("expected empty identified reconciliation acceptance")
            return
        }
        #expect(atom.repo(repo.id)?.worktrees.isEmpty == true)
        #expect(acceptance.delta.addedWorktreeIds.isEmpty)
        #expect(acceptance.delta.preservedWorktreeIds.isEmpty)
        #expect(acceptance.delta.removedWorktrees == [.init(id: existingWorktree.id, path: existingWorktree.path)])
        #expect(acceptance.delta.didChange)
    }

    @Test(
        "scanned reconciliation preserves identity by path, main-worktree role, and name",
        arguments: [
            ExistingIdentityMatchKind.path,
            ExistingIdentityMatchKind.mainWorktree,
            ExistingIdentityMatchKind.name,
        ]
    )
    func scannedReconciliationPreservesIdentityByEverySupportedMatch(
        matchKind: ExistingIdentityMatchKind
    ) throws {
        let atom = RepositoryTopologyAtom()
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-match")
        let repo = atom.addRepo(at: repoPath)
        let existingMainWorktree = try #require(atom.repo(repo.id)?.worktrees.single)
        let existingNameMatchedWorktree: Worktree
        let scannedWorktrees: RepositoryScannedWorktrees
        switch matchKind {
        case .path:
            existingNameMatchedWorktree = existingMainWorktree
            scannedWorktrees = .init(
                main: .init(name: "renamed", path: repoPath),
                linked: []
            )
        case .mainWorktree:
            existingNameMatchedWorktree = existingMainWorktree
            scannedWorktrees = .init(
                main: .init(
                    name: "moved-main",
                    path: URL(fileURLWithPath: "/tmp/agentstudio-topology-moved-main")
                ),
                linked: []
            )
        case .name:
            let namedWorktree = Worktree(
                id: UUIDv7.generate(),
                repoId: repo.id,
                name: "name-match",
                path: URL(fileURLWithPath: "/tmp/agentstudio-topology-original-name-match")
            )
            _ = atom.reconcileDiscoveredWorktrees(
                repo.id,
                worktrees: [existingMainWorktree, namedWorktree]
            )
            existingNameMatchedWorktree = namedWorktree
            scannedWorktrees = .init(
                main: .init(name: existingMainWorktree.name, path: existingMainWorktree.path),
                linked: [
                    .init(
                        name: namedWorktree.name,
                        path: URL(fileURLWithPath: "/tmp/agentstudio-topology-name-match")
                    )
                ]
            )
        }

        let result = atom.reconcileScannedWorktrees(
            repo.id,
            scannedWorktrees: scannedWorktrees,
            traceId: UUIDv7.generate()
        )

        guard case .accepted(let acceptance) = result else {
            Issue.record("expected reconciliation acceptance")
            return
        }
        #expect(atom.worktree(existingNameMatchedWorktree.id)?.id == existingNameMatchedWorktree.id)
        #expect(acceptance.delta.preservedWorktreeIds.contains(existingNameMatchedWorktree.id))
        #expect(acceptance.delta.addedWorktreeIds.isEmpty)
        #expect(acceptance.delta.removedWorktrees.isEmpty)
    }

    @Test("scanned reconciliation reports mixed preserved added and removed identities")
    func scannedReconciliationReportsMixedIdentityDelta() throws {
        let atom = RepositoryTopologyAtom()
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-mixed")
        let preservedPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-preserved")
        let removedPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-removed")
        let addedPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-added")
        let repo = atom.addRepo(at: repoPath)
        let mainWorktree = try #require(atom.repo(repo.id)?.worktrees.single)
        let preservedWorktree = Worktree(
            id: UUIDv7.generate(),
            repoId: repo.id,
            name: "preserved",
            path: preservedPath
        )
        let removedWorktree = Worktree(
            id: UUIDv7.generate(),
            repoId: repo.id,
            name: "removed",
            path: removedPath
        )
        _ = atom.reconcileDiscoveredWorktrees(
            repo.id,
            worktrees: [mainWorktree, preservedWorktree, removedWorktree]
        )

        let result = atom.reconcileScannedWorktrees(
            repo.id,
            scannedWorktrees: .init(
                main: .init(name: mainWorktree.name, path: mainWorktree.path),
                linked: [
                    .init(name: preservedWorktree.name, path: preservedPath),
                    .init(name: "added", path: addedPath),
                ]
            ),
            traceId: UUIDv7.generate()
        )

        guard case .accepted(let acceptance) = result else {
            Issue.record("expected mixed reconciliation acceptance")
            return
        }
        let finalWorktrees = try #require(atom.repo(repo.id)?.worktrees)
        let addedWorktree = try #require(finalWorktrees.first(where: { $0.path == addedPath }))
        #expect(acceptance.delta.preservedWorktreeIds == [mainWorktree.id, preservedWorktree.id])
        #expect(acceptance.delta.addedWorktreeIds == [addedWorktree.id])
        #expect(acceptance.delta.removedWorktrees == [.init(id: removedWorktree.id, path: removedPath)])
        #expect(acceptance.delta.didChange)
    }

    @Test("identical scanned reconciliation reports accepted no change")
    func identicalScannedReconciliationReportsAcceptedNoChange() throws {
        let atom = RepositoryTopologyAtom()
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-identical")
        let repo = atom.addRepo(at: repoPath)
        let existingWorktree = try #require(atom.repo(repo.id)?.worktrees.single)

        let result = atom.reconcileScannedWorktrees(
            repo.id,
            scannedWorktrees: .init(
                main: .init(
                    name: existingWorktree.name,
                    path: existingWorktree.path
                ),
                linked: []
            ),
            traceId: UUIDv7.generate()
        )

        guard case .accepted(let acceptance) = result else {
            Issue.record("expected identical reconciliation acceptance")
            return
        }
        #expect(!acceptance.delta.didChange)
        #expect(acceptance.delta.preservedWorktreeIds == [existingWorktree.id])
        #expect(acceptance.delta.addedWorktreeIds.isEmpty)
        #expect(acceptance.delta.removedWorktrees.isEmpty)
    }
}
