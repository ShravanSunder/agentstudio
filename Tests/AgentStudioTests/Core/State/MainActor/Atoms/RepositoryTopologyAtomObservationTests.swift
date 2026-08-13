import AgentStudioInfrastructure
import Foundation
import Observation
import Testing

@testable import AgentStudioCore

private final class RepositoryTopologyKeyedObservationFlag: @unchecked Sendable {
    var didFire = false
}

@MainActor
@Suite("RepositoryTopologyAtom keyed observation")
struct RepositoryTopologyAtomObservationTests {
    @Test("keyed repository lookup ignores unrelated metadata change")
    func keyedRepositoryLookupIgnoresUnrelatedMetadataChange() {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let observedRepository = coordinator.addRepo(
            at: URL(fileURLWithPath: "/tmp/agentstudio-topology-observed-repository")
        )
        let unrelatedRepository = coordinator.addRepo(
            at: URL(fileURLWithPath: "/tmp/agentstudio-topology-unrelated-repository")
        )
        let invalidation = RepositoryTopologyKeyedObservationFlag()

        withObservationTracking {
            _ = atom.repo(observedRepository.id)?.isFavorite
        } onChange: {
            invalidation.didFire = true
        }

        coordinator.setRepoFavorite(unrelatedRepository.id, isFavorite: true)

        #expect(invalidation.didFire == false)
    }

    @Test("keyed worktree lookup invalidates only for the observed worktree")
    func keyedWorktreeLookupInvalidatesOnlyForObservedWorktree() throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let observedRepository = coordinator.addRepo(
            at: URL(fileURLWithPath: "/tmp/agentstudio-topology-observed-worktree")
        )
        let unrelatedRepository = coordinator.addRepo(
            at: URL(fileURLWithPath: "/tmp/agentstudio-topology-unrelated-worktree")
        )
        let observedWorktree = try #require(observedRepository.worktrees.single)
        let unrelatedWorktree = try #require(unrelatedRepository.worktrees.single)
        let unrelatedInvalidation = RepositoryTopologyKeyedObservationFlag()

        withObservationTracking {
            _ = atom.worktree(observedWorktree.id)?.note
        } onChange: {
            unrelatedInvalidation.didFire = true
        }

        try coordinator.updateWorktreeNote(unrelatedWorktree.id, note: "unrelated")
        #expect(unrelatedInvalidation.didFire == false)

        let relatedInvalidation = RepositoryTopologyKeyedObservationFlag()
        withObservationTracking {
            _ = atom.worktree(observedWorktree.id)?.note
        } onChange: {
            relatedInvalidation.didFire = true
        }

        try coordinator.updateWorktreeNote(observedWorktree.id, note: "observed")
        #expect(relatedInvalidation.didFire)
    }

    @Test("structural membership ignores metadata changes and observes reorder")
    func structuralMembershipIgnoresMetadataChangesAndObservesReorder() {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let firstRepository = coordinator.addRepo(
            at: URL(fileURLWithPath: "/tmp/agentstudio-topology-membership-first")
        )
        _ = coordinator.addRepo(
            at: URL(fileURLWithPath: "/tmp/agentstudio-topology-membership-second")
        )
        let metadataInvalidation = RepositoryTopologyKeyedObservationFlag()

        withObservationTracking {
            _ = atom.repositoryIdsInOrder
            _ = atom.worktreeIdsInOrder
        } onChange: {
            metadataInvalidation.didFire = true
        }

        coordinator.setRepoFavorite(firstRepository.id, isFavorite: true)
        #expect(metadataInvalidation.didFire == false)

        let reorderInvalidation = RepositoryTopologyKeyedObservationFlag()
        withObservationTracking {
            _ = atom.repositoryIdsInOrder
            _ = atom.worktreeIdsInOrder
        } onChange: {
            reorderInvalidation.didFire = true
        }

        installTopology(atom: atom, repositories: Array(atom.repos.reversed()))
        #expect(reorderInvalidation.didFire)
    }

    @Test("keyed lookup observes removal and equal write is suppressed")
    func keyedLookupObservesRemovalAndEqualWriteIsSuppressed() {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repository = coordinator.addRepo(
            at: URL(fileURLWithPath: "/tmp/agentstudio-topology-keyed-removal")
        )
        coordinator.setRepoFavorite(repository.id, isFavorite: true)
        let equalWriteInvalidation = RepositoryTopologyKeyedObservationFlag()

        withObservationTracking {
            _ = atom.repo(repository.id)?.isFavorite
        } onChange: {
            equalWriteInvalidation.didFire = true
        }

        coordinator.setRepoFavorite(repository.id, isFavorite: true)
        #expect(equalWriteInvalidation.didFire == false)

        let removalInvalidation = RepositoryTopologyKeyedObservationFlag()
        withObservationTracking {
            _ = atom.repo(repository.id)
        } onChange: {
            removalInvalidation.didFire = true
        }

        coordinator.removeRepo(repository.id)
        #expect(removalInvalidation.didFire)
        #expect(atom.repo(repository.id) == nil)
    }

    @Test("cold topology snapshot remains equal to keyed lookups")
    func coldTopologySnapshotRemainsEqualToKeyedLookups() throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repository = coordinator.addRepo(
            at: URL(fileURLWithPath: "/tmp/agentstudio-topology-cold-snapshot")
        )
        let worktree = try #require(repository.worktrees.single)

        coordinator.setRepoFavorite(repository.id, isFavorite: true)
        try coordinator.updateWorktreeNote(worktree.id, note: "snapshot parity")

        let snapshot = atom.captureReadSnapshot()

        #expect(snapshot.repo(repository.id) == atom.repo(repository.id))
        #expect(snapshot.worktree(worktree.id) == atom.worktree(worktree.id))
    }

    @Test("scoped path lookup invalidates when availability rebuilds the path index")
    func scopedPathLookupInvalidatesWhenPathIndexRegenerates() throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repository = coordinator.addRepo(
            at: URL(fileURLWithPath: "/tmp/agentstudio-topology-scoped-path-index")
        )
        let worktree = try #require(repository.worktrees.single)
        let invalidation = RepositoryTopologyKeyedObservationFlag()

        withObservationTracking {
            _ = atom.repoAndWorktree(containing: worktree.path, among: [worktree.id])
        } onChange: {
            invalidation.didFire = true
        }

        coordinator.markRepoUnavailable(repository.id)

        #expect(invalidation.didFire)
    }

}
