import Foundation
import Observation
import Testing

@testable import AgentStudio

private final class RepositoryTopologyObservationFlag: @unchecked Sendable {
    var didFire = false
}

@MainActor
@Suite("RepositoryTopologyAtom")
struct RepositoryTopologyAtomTests {
    enum ExistingIdentityMatchKind: Sendable {
        case path
        case mainWorktree
        case name
    }

    @Test("path lookup resolves current repository metadata without rebuilding structural index")
    func pathLookupResolvesCurrentRepositoryMetadata() throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-current-metadata")
        let repo = coordinator.addRepo(at: repoPath)
        let generation = atom.worktreePathIndexGeneration

        coordinator.setRepoFavorite(repo.id, isFavorite: true)
        coordinator.updateRepoNote(repo.id, note: "current note")
        try coordinator.setRepoTags(["current"], repositoryID: repo.id)

        let match = try #require(atom.repoAndWorktree(containing: repoPath))
        #expect(match.repo.isFavorite)
        #expect(match.repo.note == "current note")
        #expect(match.repo.tags == ["current"])
        #expect(atom.worktreePathIndexGeneration == generation)
    }

    @Test("path lookup resolves current worktree metadata without rebuilding structural index")
    func pathLookupResolvesCurrentWorktreeMetadata() throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-current-worktree-metadata")
        let repo = coordinator.addRepo(at: repoPath)
        let worktree = try #require(repo.worktrees.single)
        let generation = atom.worktreePathIndexGeneration

        try coordinator.updateWorktreeNote(worktree.id, note: "worktree note")

        let match = try #require(atom.repoAndWorktree(containing: repoPath))
        #expect(match.worktree.note == "worktree note")
        #expect(atom.worktreePathIndexGeneration == generation)
    }

    @Test("keyed repository lookup invalidates observation after metadata change")
    func keyedRepositoryLookupInvalidatesObservationAfterMetadataChange() {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repo = coordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-topology-observed-metadata"))
        let invalidation = RepositoryTopologyObservationFlag()

        withObservationTracking {
            _ = atom.repo(repo.id)?.isFavorite
        } onChange: {
            invalidation.didFire = true
        }

        coordinator.setRepoFavorite(repo.id, isFavorite: true)

        #expect(invalidation.didFire)
    }

    @Test("missing keyed repository lookup invalidates observation after structural insertion")
    func missingKeyedRepositoryLookupInvalidatesObservationAfterStructuralInsertion() {
        let atom = RepositoryTopologyAtom()
        let repositoryID = UUIDv7.generate()
        let repository = Repo(
            id: repositoryID,
            name: "observed-insertion",
            repoPath: URL(fileURLWithPath: "/tmp/agentstudio-topology-observed-insertion")
        )
        let invalidation = RepositoryTopologyObservationFlag()

        withObservationTracking {
            _ = atom.repo(repositoryID)
        } onChange: {
            invalidation.didFire = true
        }

        installTopology(atom: atom, repositories: [repository])

        #expect(invalidation.didFire)
    }

    @Test("batched topology mutation defers path index rebuild until batch exits")
    func batchedTopologyMutationDefersPathIndexRebuildUntilBatchExits() {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let startingGeneration = atom.worktreePathIndexGeneration
        let repoAPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-batch-a")
        let repoBPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-batch-b")

        coordinator.performBatchedTopologyMutation {
            let repoA = coordinator.addRepo(at: repoAPath)
            _ = coordinator.addRepo(at: repoBPath)
            coordinator.reconcileDiscoveredWorktrees(
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

    @Test("accepted equal topology replacement suppresses index reconstruction")
    func acceptedEqualTopologyReplacementSuppressesIndexReconstruction() {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        _ = coordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-topology-equal-replacement"))
        let generationBeforeEqualReplacement = atom.worktreePathIndexGeneration

        installTopology(atom: atom, repositories: atom.repos)

        #expect(atom.worktreePathIndexGeneration == generationBeforeEqualReplacement)
    }

    @Test("repo tags mutate as topology state")
    func repoTagsMutateAsTopologyState() throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repo = coordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-topology-tags"))

        try coordinator.setRepoTags(["client", "active"], repositoryID: repo.id)

        #expect(atom.repo(repo.id)?.tags == ["active", "client"])
    }

    @Test("repo tag validation rejects unsafe and duplicate values")
    func repoTagValidationRejectsUnsafeAndDuplicateValues() {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repo = coordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-topology-tag-validation"))

        #expect(throws: RepositoryTopologyMutationError.invalidRepositoryTag(" leading")) {
            try coordinator.setRepoTags([" leading"], repositoryID: repo.id)
        }
        #expect(throws: RepositoryTopologyMutationError.invalidRepositoryTag("spoof\u{2066}tag")) {
            try coordinator.setRepoTags(["spoof\u{2066}tag"], repositoryID: repo.id)
        }
        #expect(throws: RepositoryTopologyMutationError.duplicateRepositoryTag("wip")) {
            try coordinator.setRepoTags(["wip", "wip"], repositoryID: repo.id)
        }
        #expect(atom.repo(repo.id)?.tags.isEmpty == true)
    }

    @Test("sealed topology replacement rejects duplicate stable keys before atom assignment")
    func sealedTopologyReplacementRejectsDuplicateStableKeys() {
        let repositoryPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-duplicate-stable-key")
        let firstRepositoryID = UUIDv7.generate()
        let secondRepositoryID = UUIDv7.generate()
        let firstRepository = Repo(
            id: firstRepositoryID,
            name: "first",
            repoPath: repositoryPath,
            worktrees: [
                Worktree(
                    id: UUIDv7.generate(),
                    repoId: firstRepositoryID,
                    name: "first",
                    path: repositoryPath.appending(path: "first")
                )
            ]
        )
        let secondRepository = Repo(
            id: secondRepositoryID,
            name: "second",
            repoPath: repositoryPath,
            worktrees: [
                Worktree(
                    id: UUIDv7.generate(),
                    repoId: secondRepositoryID,
                    name: "second",
                    path: repositoryPath.appending(path: "second")
                )
            ]
        )

        let duplicateRepositoryRejection = topologyRejection(
            repositories: [firstRepository, secondRepository],
            watchedPaths: []
        )
        let duplicateWorktreePath = repositoryPath.appending(path: "duplicate-worktree")
        let repositoryWithDuplicateWorktrees = Repo(
            id: firstRepositoryID,
            name: "worktree-duplicates",
            repoPath: repositoryPath.appending(path: "worktree-owner"),
            worktrees: [
                Worktree(
                    id: UUIDv7.generate(),
                    repoId: firstRepositoryID,
                    name: "one",
                    path: duplicateWorktreePath
                ),
                Worktree(
                    id: UUIDv7.generate(),
                    repoId: firstRepositoryID,
                    name: "two",
                    path: duplicateWorktreePath
                ),
            ]
        )
        let duplicateWorktreeRejection = topologyRejection(
            repositories: [repositoryWithDuplicateWorktrees],
            watchedPaths: []
        )
        let watchedPath = WatchedPath(path: repositoryPath.appending(path: "watched"))
        let duplicateWatchedPath = WatchedPath(path: watchedPath.path)
        let duplicateWatchedPathRejection = topologyRejection(
            repositories: [],
            watchedPaths: [watchedPath, duplicateWatchedPath]
        )

        #expect(
            duplicateRepositoryRejection
                == .duplicateRepositoryStableKey(StableKey.fromPath(repositoryPath))
        )
        #expect(
            duplicateWorktreeRejection
                == .duplicateWorktreeStableKey(StableKey.fromPath(duplicateWorktreePath))
        )
        #expect(
            duplicateWatchedPathRejection
                == .duplicateWatchedPathStableKey(StableKey.fromPath(watchedPath.path))
        )
    }

    @Test("worktree reconciliation preserves existing notes for matched worktrees")
    func worktreeReconciliationPreservesExistingNotesForMatchedWorktrees() throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-preserve-notes")
        let repo = coordinator.addRepo(at: repoPath)
        let mainWorktree = try #require(atom.repo(repo.id)?.worktrees.single)
        try coordinator.updateWorktreeNote(mainWorktree.id, note: "keep this note")

        coordinator.reconcileDiscoveredWorktrees(
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

    @Test("worktree reconciliation consumes an existing identity only once")
    func worktreeReconciliationConsumesExistingIdentityOnlyOnce() throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-existing-identity")
        let renamedPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-renamed/existing-identity")
        let repo = coordinator.addRepo(at: repoPath)
        try coordinator.updateWorktreeNote(repo.worktrees[0].id, note: "keep")
        let existingMainWorktree = try #require(atom.repo(repo.id)?.worktrees.single)

        coordinator.reconcileDiscoveredWorktrees(
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
        #expect(reconciledWorktrees[0].note == "keep")
        #expect(reconciledWorktrees[1].id != existingMainWorktree.id)
    }

    @Test("scanned reconciliation mints UUIDv7 identities and reports an exact delta")
    func scannedReconciliationMintsUUIDv7IdentitiesAndReportsExactDelta() throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-scanned")
        let linkedPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-linked/scanned")
        let repo = coordinator.addRepo(at: repoPath)
        let existingMainWorktree = try #require(atom.repo(repo.id)?.worktrees.single)
        let traceId = UUIDv7.generate()

        let result = coordinator.reconcileScannedWorktrees(
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
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let firstRepo = coordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-topology-first"))
        let secondRepo = coordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-topology-second"))
        let stateBeforeRejection = atom.repos
        let generationBeforeRejection = atom.worktreePathIndexGeneration
        let conflictingWorktreeId = UUIDv7.generate()

        let result = coordinator.reconcileDiscoveredWorktrees(
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
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let firstRepo = coordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-reassociation-first"))
        let secondRepo = coordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-reassociation-second"))
        coordinator.markRepoUnavailable(firstRepo.id)
        let reposBeforeRejection = atom.repos
        let unavailableRepoIdsBeforeRejection = atom.unavailableRepoIds
        let generationBeforeRejection = atom.worktreePathIndexGeneration

        let result = coordinator.reassociateRepo(
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
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let oldPath = URL(fileURLWithPath: "/tmp/agentstudio-reassociation-old")
        let relocatedPath = URL(fileURLWithPath: "/tmp/agentstudio-reassociation-new")
        let repo = coordinator.addRepo(at: oldPath)
        let existingWorktree = try #require(atom.repo(repo.id)?.worktrees.single)
        coordinator.markRepoUnavailable(repo.id)
        let generationBeforeReassociation = atom.worktreePathIndexGeneration

        let result = coordinator.reassociateRepo(
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
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let firstRepo = coordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-reassociation-key-first"))
        let secondRepo = coordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-reassociation-key-second"))
        coordinator.markRepoUnavailable(firstRepo.id)
        let reposBeforeRejection = atom.repos
        let unavailableRepoIdsBeforeRejection = atom.unavailableRepoIds
        let generationBeforeRejection = atom.worktreePathIndexGeneration

        let result = coordinator.reassociateRepo(
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
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repo = coordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-topology-empty"))
        let existingWorktree = try #require(atom.repo(repo.id)?.worktrees.single)

        let result = coordinator.reconcileDiscoveredWorktrees(
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

    @Test("ensure main worktree repairs with UUIDv7 without rewriting persisted identities")
    func ensureMainWorktreeRepairsEmptyUnavailableRepository() throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-ensure-main-repair")
        let persistedRepositoryID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let persistedSiblingRepositoryID = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
        let persistedSiblingWorktreeID = UUID(uuidString: "10000000-0000-4000-8000-000000000003")!
        let siblingPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-ensure-main-sibling")
        installTopology(
            atom: atom,
            repositories: [
                Repo(
                    id: persistedRepositoryID,
                    name: repoPath.lastPathComponent,
                    repoPath: repoPath
                ),
                Repo(
                    id: persistedSiblingRepositoryID,
                    name: siblingPath.lastPathComponent,
                    repoPath: siblingPath,
                    worktrees: [
                        Worktree(
                            id: persistedSiblingWorktreeID,
                            repoId: persistedSiblingRepositoryID,
                            name: siblingPath.lastPathComponent,
                            path: siblingPath,
                            isMainWorktree: true
                        )
                    ]
                ),
            ]
        )
        coordinator.markRepoUnavailable(persistedRepositoryID)
        let generationBeforeRepair = atom.worktreePathIndexGeneration

        let repairedWorktree = coordinator.ensureMainWorktree(at: repoPath)

        let repairedRepository = try #require(atom.repo(persistedRepositoryID))
        #expect(repairedRepository.worktrees == [repairedWorktree])
        #expect(UUIDv7.isV7(repairedWorktree.id))
        #expect(repairedRepository.id == persistedRepositoryID)
        #expect(atom.repo(persistedSiblingRepositoryID)?.worktrees.single?.id == persistedSiblingWorktreeID)
        #expect(repairedWorktree.repoId == persistedRepositoryID)
        #expect(repairedWorktree.path == repoPath.standardizedFileURL)
        #expect(repairedWorktree.isMainWorktree)
        #expect(!atom.isRepoUnavailable(persistedRepositoryID))
        #expect(atom.worktreePathIndexGeneration == generationBeforeRepair + 1)
        #expect(atom.repoAndWorktree(containing: repoPath)?.worktree.id == repairedWorktree.id)
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
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-match")
        let repo = coordinator.addRepo(at: repoPath)
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
            _ = coordinator.reconcileDiscoveredWorktrees(
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

        let result = coordinator.reconcileScannedWorktrees(
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
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-mixed")
        let preservedPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-preserved")
        let removedPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-removed")
        let addedPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-added")
        let repo = coordinator.addRepo(at: repoPath)
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
        _ = coordinator.reconcileDiscoveredWorktrees(
            repo.id,
            worktrees: [mainWorktree, preservedWorktree, removedWorktree]
        )

        let result = coordinator.reconcileScannedWorktrees(
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
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-identical")
        let repo = coordinator.addRepo(at: repoPath)
        let existingWorktree = try #require(atom.repo(repo.id)?.worktrees.single)

        let result = coordinator.reconcileScannedWorktrees(
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

@MainActor
private func makeTopologyMutationCoordinator(atom: RepositoryTopologyAtom) -> WorkspaceMutationCoordinator {
    AtomRegistry(workspaceRepositoryTopology: atom).workspaceMutationCoordinator
}

@MainActor
private func installTopology(atom: RepositoryTopologyAtom, repositories: [Repo]) {
    switch RepositoryTopologyReplacement.prepare(
        repositories: repositories,
        watchedPaths: atom.watchedPaths,
        unavailableRepositoryIDs: atom.unavailableRepoIds
    ) {
    case .prepared(let replacement):
        atom.replaceTopology(replacement)
    case .rejected(let rejection):
        Issue.record("invalid topology test fixture: \(rejection)")
    }
}

private func topologyRejection(
    repositories: [Repo],
    watchedPaths: [WatchedPath]
) -> RepositoryTopologyIdentityRejection? {
    switch RepositoryTopologyReplacement.prepare(
        repositories: repositories,
        watchedPaths: watchedPaths,
        unavailableRepositoryIDs: []
    ) {
    case .prepared:
        return nil
    case .rejected(let rejection):
        return rejection
    }
}
