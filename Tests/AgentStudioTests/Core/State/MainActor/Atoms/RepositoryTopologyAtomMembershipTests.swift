import AgentStudioInfrastructure
import Foundation
import Observation
import Testing

@testable import AgentStudioCore

private final class RepositoryMembershipObservationFlag: @unchecked Sendable {
    var didFire = false
}

@MainActor
@Suite("RepositoryTopologyAtom membership facts")
struct RepositoryTopologyAtomMembershipTests {
    @Test("worktree repository lookup ignores worktree metadata")
    func worktreeRepositoryLookupIgnoresMetadata() throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repository = coordinator.addRepo(
            at: URL(fileURLWithPath: "/tmp/topology-membership-metadata")
        )
        let worktree = try #require(repository.worktrees.single)
        let observation = RepositoryMembershipObservationFlag()

        withObservationTracking {
            _ = atom.repositoryId(containing: worktree.id)
        } onChange: {
            observation.didFire = true
        }

        try coordinator.updateWorktreeNote(worktree.id, note: "Unrelated metadata")

        #expect(observation.didFire == false)
        #expect(atom.repositoryId(containing: worktree.id) == repository.id)
    }

    @Test("worktree membership observes addition and removal")
    func worktreeMembershipObservesAdditionAndRemoval() throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let membershipAddition = RepositoryMembershipObservationFlag()

        withObservationTracking {
            _ = atom.repositoryMembershipWorktreeIds
        } onChange: {
            membershipAddition.didFire = true
        }

        let repository = coordinator.addRepo(
            at: URL(fileURLWithPath: "/tmp/topology-membership-addition")
        )
        let worktree = try #require(repository.worktrees.single)

        #expect(membershipAddition.didFire)
        #expect(atom.repositoryId(containing: worktree.id) == repository.id)

        let membershipRemoval = RepositoryMembershipObservationFlag()
        withObservationTracking {
            _ = atom.repositoryMembershipWorktreeIds
        } onChange: {
            membershipRemoval.didFire = true
        }

        coordinator.removeRepo(repository.id)

        #expect(membershipRemoval.didFire)
        #expect(atom.repositoryId(containing: worktree.id) == nil)
    }
}
