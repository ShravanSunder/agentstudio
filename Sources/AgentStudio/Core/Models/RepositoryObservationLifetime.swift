import AgentStudioInfrastructure
import Foundation

package struct RepositoryObservationLifetime: Equatable, Sendable {
    let launchEpoch: UUID
    let revision: UInt64
}

package struct WorktreeObservationLifetime: Equatable, Sendable {
    let launchEpoch: UUID
    let revision: UInt64
}

package enum RepositoryFactObservationLifetime: Equatable, Sendable {
    case unscoped
    case repository(RepositoryObservationLifetime)
    case worktree(WorktreeObservationLifetime)
}

/// Request-scoped values survive actor hops and are attached before facts enter the bus.
enum RepositoryObservationRequestContext {
    @TaskLocal static var worktree: WorktreeObservationLifetime?
    @TaskLocal static var repository: RepositoryObservationLifetime?
}

struct RepositoryObservationIndex {
    private struct CheckoutIdentity: Equatable {
        let repositoryID: UUID
        let path: URL
    }
    private struct FamilyIdentity: Equatable {
        let path: URL
        let checkouts: [UUID: CheckoutIdentity]
    }
    private let launchEpoch = UUIDv7.generate()
    private var revision: UInt64 = 0
    private var checkouts: [UUID: CheckoutIdentity] = [:]
    private var families: [UUID: FamilyIdentity] = [:]
    private(set) var repositoryLifetimes: [UUID: RepositoryObservationLifetime] = [:]
    private(set) var worktreeLifetimes: [UUID: WorktreeObservationLifetime] = [:]

    mutating func replace(repositories: [Repo], absences: RepositoryTopologyAbsenceRecords) {
        var nextCheckouts: [UUID: CheckoutIdentity] = [:]
        var nextFamilies: [UUID: FamilyIdentity] = [:]
        for repository in repositories where absences.repositories[repository.id] == nil {
            var members: [UUID: CheckoutIdentity] = [:]
            for worktree in repository.worktrees where absences.worktrees[worktree.id] == nil {
                let identity = CheckoutIdentity(repositoryID: repository.id, path: worktree.path)
                members[worktree.id] = identity
                nextCheckouts[worktree.id] = identity
                if checkouts[worktree.id] != identity {
                    revision &+= 1
                    worktreeLifetimes[worktree.id] = .init(launchEpoch: launchEpoch, revision: revision)
                }
            }
            let identity = FamilyIdentity(path: repository.repoPath, checkouts: members)
            nextFamilies[repository.id] = identity
            if families[repository.id] != identity {
                revision &+= 1
                repositoryLifetimes[repository.id] = .init(launchEpoch: launchEpoch, revision: revision)
            }
        }
        checkouts = nextCheckouts
        families = nextFamilies
        worktreeLifetimes = worktreeLifetimes.filter { nextCheckouts[$0.key] != nil }
        repositoryLifetimes = repositoryLifetimes.filter { nextFamilies[$0.key] != nil }
    }
}
