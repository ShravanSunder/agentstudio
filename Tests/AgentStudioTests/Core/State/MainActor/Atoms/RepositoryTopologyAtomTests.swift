import AgentStudioInfrastructure
import Foundation
import Observation
import Testing

@testable import AgentStudioCore

private final class RepositoryTopologyObservationFlag: @unchecked Sendable {
    var didFire = false
}

enum CWDAssociationExpectedWorktree: String, Sendable {
    case main
    case nestedLinked
    case noMatch
}

struct CWDAssociationLookupCase: CustomTestStringConvertible, Sendable {
    static let allCases: [Self] = [
        .init(
            name: "exact-root",
            cwdPath: "/tmp/agentstudio-cwd-association/repo",
            expectedWorktree: .main
        ),
        .init(
            name: "main-descendant",
            cwdPath: "/tmp/agentstudio-cwd-association/repo/Sources/Feature",
            expectedWorktree: .main
        ),
        .init(
            name: "deepest-nested-linked-descendant",
            cwdPath: "/tmp/agentstudio-cwd-association/repo/worktrees/feature/Sources",
            expectedWorktree: .nestedLinked
        ),
        .init(
            name: "component-prefix-collision",
            cwdPath: "/tmp/agentstudio-cwd-association/repo-tools",
            expectedWorktree: .noMatch
        ),
        .init(
            name: "deleted-unregistered-path",
            cwdPath: "/tmp/agentstudio-cwd-association/deleted/path",
            expectedWorktree: .noMatch
        ),
    ]

    let name: String
    let cwdPath: String
    let expectedWorktree: CWDAssociationExpectedWorktree

    var testDescription: String { name }
}

@MainActor
@Suite("RepositoryTopologyAtom")
struct RepositoryTopologyAtomTests {
    @Test(
        "CWD association uses deepest component-boundary containment",
        arguments: CWDAssociationLookupCase.allCases
    )
    func cwdAssociationUsesDeepestComponentBoundaryContainment(
        lookupCase: CWDAssociationLookupCase
    ) throws {
        let atom = RepositoryTopologyAtom()
        let repositoryID = UUIDv7.generate()
        let mainWorktreeID = UUIDv7.generate()
        let nestedLinkedWorktreeID = UUIDv7.generate()
        let repositoryPath = URL(fileURLWithPath: "/tmp/agentstudio-cwd-association/repo")
        let nestedLinkedWorktreePath = repositoryPath.appending(path: "worktrees/feature")
        installTopology(
            atom: atom,
            repositories: [
                Repo(
                    id: repositoryID,
                    name: repositoryPath.lastPathComponent,
                    repoPath: repositoryPath,
                    worktrees: [
                        Worktree(
                            id: mainWorktreeID,
                            repoId: repositoryID,
                            name: repositoryPath.lastPathComponent,
                            path: repositoryPath,
                            isMainWorktree: true
                        ),
                        Worktree(
                            id: nestedLinkedWorktreeID,
                            repoId: repositoryID,
                            name: nestedLinkedWorktreePath.lastPathComponent,
                            path: nestedLinkedWorktreePath
                        ),
                    ]
                )
            ]
        )

        let association = atom.repoAndWorktree(
            containing: URL(fileURLWithPath: lookupCase.cwdPath)
        )

        switch lookupCase.expectedWorktree {
        case .main:
            #expect(association?.repo.id == repositoryID)
            #expect(association?.worktree.id == mainWorktreeID)
        case .nestedLinked:
            #expect(association?.repo.id == repositoryID)
            #expect(association?.worktree.id == nestedLinkedWorktreeID)
        case .noMatch:
            #expect(association == nil)
        }
    }

    @Test("CWD association follows remove and re-registration with fresh identities")
    func cwdAssociationFollowsRemoveAndReregistrationWithFreshIdentities() throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repositoryPath = URL(fileURLWithPath: "/tmp/agentstudio-cwd-reregistration/repo")
        let paneCWD = repositoryPath.appending(path: "Sources/Feature")
        let originalRepository = coordinator.addRepo(at: repositoryPath)
        let originalWorktree = try #require(originalRepository.worktrees.single)

        let originalAssociation = try #require(atom.repoAndWorktree(containing: paneCWD))
        #expect(originalAssociation.repo.id == originalRepository.id)
        #expect(originalAssociation.worktree.id == originalWorktree.id)

        coordinator.removeRepo(originalRepository.id)

        #expect(atom.repoAndWorktree(containing: paneCWD) == nil)

        let reregisteredRepository = coordinator.addRepo(at: repositoryPath)
        let reregisteredWorktree = try #require(reregisteredRepository.worktrees.single)
        let reregisteredAssociation = try #require(atom.repoAndWorktree(containing: paneCWD))

        #expect(reregisteredRepository.id != originalRepository.id)
        #expect(reregisteredWorktree.id != originalWorktree.id)
        #expect(reregisteredAssociation.repo.id == reregisteredRepository.id)
        #expect(reregisteredAssociation.worktree.id == reregisteredWorktree.id)
        #expect(reregisteredAssociation.repo.repoPath == repositoryPath.standardizedFileURL)
        #expect(reregisteredAssociation.worktree.path == repositoryPath.standardizedFileURL)
    }

    @Test("stable-key lookups resolve the same live entities as UUID lookups")
    func stableKeyLookupsResolveTheSameLiveEntitiesAsUUIDLookups() throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repository = coordinator.addRepo(
            at: URL(fileURLWithPath: "/tmp/agentstudio-topology-stable-key")
        )
        let worktree = try #require(repository.worktrees.single)

        #expect(atom.repo(stableKey: repository.stableKey) == atom.repo(repository.id))
        #expect(atom.worktree(stableKey: worktree.stableKey) == atom.worktree(worktree.id))

        coordinator.setRepoFavorite(repository.id, isFavorite: true)
        try coordinator.updateWorktreeNote(worktree.id, note: "current")

        #expect(atom.repo(stableKey: repository.stableKey)?.isFavorite == true)
        #expect(atom.worktree(stableKey: worktree.stableKey)?.note == "current")
    }

    @Test("stable-key lookups refresh after path changes, reconciliation, and removal")
    func stableKeyLookupsRefreshAfterStructuralChanges() throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let originalPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-stable-key-original")
        let movedPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-stable-key-moved")
        let linkedPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-stable-key-linked")
        let repository = coordinator.addRepo(at: originalPath)
        let originalRepositoryStableKey = repository.stableKey
        let originalWorktreeStableKey = try #require(repository.worktrees.single).stableKey

        _ = coordinator.reassociateRepo(
            repository.id,
            to: movedPath,
            discoveredWorktrees: [
                Worktree(
                    repoId: repository.id,
                    name: movedPath.lastPathComponent,
                    path: movedPath,
                    isMainWorktree: true
                ),
                Worktree(
                    repoId: repository.id,
                    name: linkedPath.lastPathComponent,
                    path: linkedPath
                ),
            ]
        )

        #expect(atom.repo(stableKey: originalRepositoryStableKey) == nil)
        #expect(atom.worktree(stableKey: originalWorktreeStableKey) == nil)
        #expect(atom.repo(stableKey: StableKey.fromPath(movedPath))?.id == repository.id)
        #expect(atom.worktree(stableKey: StableKey.fromPath(linkedPath))?.path == linkedPath)

        coordinator.removeRepo(repository.id)

        #expect(atom.repo(stableKey: StableKey.fromPath(movedPath)) == nil)
        #expect(atom.worktree(stableKey: StableKey.fromPath(linkedPath)) == nil)
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
            repoPath: URL(fileURLWithPath: "/tmp/agentstudio-topology-observed-insertion"),
            worktrees: [
                Worktree(
                    repoId: repositoryID,
                    name: "observed-insertion",
                    path: URL(fileURLWithPath: "/tmp/agentstudio-topology-observed-insertion"),
                    isMainWorktree: true
                )
            ]
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

    @Test("sealed topology replacement rejects duplicate roots even when unavailable")
    func sealedTopologyReplacementRejectsUnavailableDuplicateRoots() {
        let repositoryID = UUIDv7.generate()
        let repositoryPath = URL(filePath: "/tmp/agentstudio-degraded-duplicate-root")
        let duplicateRootWorktrees = [
            Worktree(
                id: UUIDv7.generate(),
                repoId: repositoryID,
                name: "root-one",
                path: repositoryPath
            ),
            Worktree(
                id: UUIDv7.generate(),
                repoId: repositoryID,
                name: "root-two",
                path: repositoryPath
            ),
        ]
        let repository = Repo(
            id: repositoryID,
            name: repositoryPath.lastPathComponent,
            repoPath: repositoryPath,
            worktrees: duplicateRootWorktrees
        )
        let preparation = RepositoryTopologyReplacement.prepare(
            repositories: [repository],
            watchedPaths: [],
            unavailableRepositoryIDs: [repositoryID]
        )

        guard case .rejected(let rejection) = preparation else {
            Issue.record("expected duplicate stable identity to remain globally rejected")
            return
        }
        #expect(rejection == .duplicateWorktreeStableKey(StableKey.fromPath(repositoryPath)))
    }

    @Test("sealed topology replacement rejects available repositories without one truthful main worktree")
    func sealedTopologyReplacementRejectsInvalidAvailableMainWorktree() {
        let repositoryID = UUIDv7.generate()
        let repositoryPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-main-invariant")
        let rootWorktree = Worktree(
            id: UUIDv7.generate(),
            repoId: repositoryID,
            name: "root",
            path: repositoryPath,
            isMainWorktree: false
        )
        let linkedWorktree = Worktree(
            id: UUIDv7.generate(),
            repoId: repositoryID,
            name: "linked",
            path: repositoryPath.appending(path: "linked"),
            isMainWorktree: false
        )

        let zeroMainRejection = topologyRejection(
            repositories: [
                Repo(
                    id: repositoryID,
                    name: "zero-main",
                    repoPath: repositoryPath,
                    worktrees: [rootWorktree, linkedWorktree]
                )
            ],
            watchedPaths: []
        )
        var multipleMainRoot = rootWorktree
        multipleMainRoot.isMainWorktree = true
        var multipleMainLinked = linkedWorktree
        multipleMainLinked.isMainWorktree = true
        let multipleMainRejection = topologyRejection(
            repositories: [
                Repo(
                    id: repositoryID,
                    name: "multiple-main",
                    repoPath: repositoryPath,
                    worktrees: [multipleMainRoot, multipleMainLinked]
                )
            ],
            watchedPaths: []
        )
        var wrongPathMain = linkedWorktree
        wrongPathMain.isMainWorktree = true
        let wrongPathMainRejection = topologyRejection(
            repositories: [
                Repo(
                    id: repositoryID,
                    name: "wrong-path-main",
                    repoPath: repositoryPath,
                    worktrees: [rootWorktree, wrongPathMain]
                )
            ],
            watchedPaths: []
        )

        #expect(zeroMainRejection == .availableRepositoryMainWorktreeMissing(repositoryID))
        #expect(multipleMainRejection == .availableRepositoryHasMultipleMainWorktrees(repositoryID))
        #expect(wrongPathMainRejection == .availableRepositoryMainWorktreePathMismatch(repositoryID))
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
        let preparedMainStableKey = atom.repositoryStableKey(for: repo.id) ?? "prepared-main-key"
        let preparedLinkedStableKey = "prepared-linked-key"

        let result = coordinator.reconcileScannedWorktrees(
            repo.id,
            scannedWorktrees: RepositoryScannedWorktrees(
                main: RepositoryScannedMainWorktree(
                    name: repoPath.lastPathComponent,
                    path: repoPath,
                    stableKey: preparedMainStableKey
                ),
                linked: [
                    RepositoryScannedLinkedWorktree(
                        name: repoPath.lastPathComponent,
                        path: linkedPath,
                        stableKey: preparedLinkedStableKey
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
        #expect(atom.worktreeStableKey(for: reconciledWorktrees[0].id) == preparedMainStableKey)
        #expect(atom.worktreeStableKey(for: reconciledWorktrees[1].id) == preparedLinkedStableKey)
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

        let generationBeforeRemoval = atom.worktreePathIndexGeneration
        let result = coordinator.unregisterWorktree(existingWorktree.id, from: repo.id)

        guard case .accepted(let acceptance) = result else {
            Issue.record("expected empty identified reconciliation acceptance")
            return
        }
        #expect(atom.repo(repo.id)?.worktrees.isEmpty == true)
        #expect(atom.isRepoUnavailable(repo.id))
        #expect(atom.worktreePathIndexGeneration == generationBeforeRemoval + 1)
        #expect(acceptance.delta.addedWorktreeIds.isEmpty)
        #expect(acceptance.delta.preservedWorktreeIds.isEmpty)
        #expect(acceptance.delta.removedWorktrees == [.init(id: existingWorktree.id, path: existingWorktree.path)])
        #expect(acceptance.delta.didChange)
    }

    @Test("availability-only changes rebuild the CWD association index")
    func availabilityOnlyChangesRebuildCWDAssociationIndex() throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-availability-index")
        let repo = coordinator.addRepo(at: repoPath)
        let worktree = try #require(atom.repo(repo.id)?.worktrees.single)
        let generationBeforeDegradation = atom.worktreePathIndexGeneration

        coordinator.markRepoUnavailable(repo.id)

        #expect(atom.worktreePathIndexGeneration == generationBeforeDegradation + 1)
        #expect(atom.repoAndWorktree(containing: repoPath) == nil)

        let generationBeforeHealing = atom.worktreePathIndexGeneration
        let healing = coordinator.reassociateRepo(
            repo.id,
            to: repoPath,
            discoveredWorktrees: [worktree]
        )

        guard case .accepted = healing else {
            Issue.record("expected exact-root reassociation acceptance")
            return
        }
        #expect(atom.worktreePathIndexGeneration == generationBeforeHealing + 1)
        #expect(atom.repoAndWorktree(containing: repoPath)?.worktree.id == worktree.id)
    }

    @Test("direct unregistration rejects a missing worktree without changing topology")
    func directUnregistrationRejectsMissingWorktree() {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repo = coordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agentstudio-topology-missing-unregister"))
        let topologyBeforeRejection = atom.repos
        let availabilityBeforeRejection = atom.unavailableRepoIds
        let generationBeforeRejection = atom.worktreePathIndexGeneration
        let missingWorktreeID = UUIDv7.generate()

        let result = coordinator.unregisterWorktree(missingWorktreeID, from: repo.id)

        #expect(result == .rejected(.worktreeNotFound(missingWorktreeID)))
        #expect(atom.repos == topologyBeforeRejection)
        #expect(atom.unavailableRepoIds == availabilityBeforeRejection)
        #expect(atom.worktreePathIndexGeneration == generationBeforeRejection)
    }

}

@MainActor
func makeTopologyMutationCoordinator(atom: RepositoryTopologyAtom) -> WorkspaceMutationCoordinator {
    CoreAtoms(workspaceRepositoryTopology: atom).workspaceMutationCoordinator
}

@MainActor
func installTopology(
    atom: RepositoryTopologyAtom,
    repositories: [Repo],
    unavailableRepositoryIDs: Set<UUID>? = nil
) {
    switch RepositoryTopologyReplacement.prepare(
        repositories: repositories,
        watchedPaths: atom.watchedPaths,
        unavailableRepositoryIDs: unavailableRepositoryIDs ?? atom.unavailableRepoIds
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
