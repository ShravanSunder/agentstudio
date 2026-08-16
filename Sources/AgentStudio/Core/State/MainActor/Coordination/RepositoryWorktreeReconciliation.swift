import Foundation

package struct RemovedWorktreeEntry: Sendable, Equatable {
    package let id: UUID
    package let path: URL

    package init(id: UUID, path: URL) {
        self.id = id
        self.path = path
    }
}

package struct WorktreeTopologyDelta: Sendable, Equatable {
    package let repoId: UUID
    package let addedWorktreeIds: [UUID]
    package let removedWorktrees: [RemovedWorktreeEntry]
    package let preservedWorktreeIds: [UUID]
    package let didChange: Bool
    package let traceId: UUID?

    package init(
        repoId: UUID,
        addedWorktreeIds: [UUID],
        removedWorktrees: [RemovedWorktreeEntry],
        preservedWorktreeIds: [UUID],
        didChange: Bool,
        traceId: UUID?
    ) {
        self.repoId = repoId
        self.addedWorktreeIds = addedWorktreeIds
        self.removedWorktrees = removedWorktrees
        self.preservedWorktreeIds = preservedWorktreeIds
        self.didChange = didChange
        self.traceId = traceId
    }
}

package struct RepositoryScannedMainWorktree: Equatable, Sendable {
    package let name: String
    package let path: URL

    package init(name: String, path: URL) {
        self.name = name
        self.path = path
    }
}

package struct RepositoryScannedLinkedWorktree: Equatable, Sendable {
    package let name: String
    package let path: URL

    package init(name: String, path: URL) {
        self.name = name
        self.path = path
    }
}

package struct RepositoryScannedWorktrees: Equatable, Sendable {
    package let main: RepositoryScannedMainWorktree
    package let linked: [RepositoryScannedLinkedWorktree]

    package init(
        main: RepositoryScannedMainWorktree,
        linked: [RepositoryScannedLinkedWorktree]
    ) {
        self.main = main
        self.linked = linked
    }
}

package struct RepositoryWorktreeReconciliationAcceptance: Equatable, Sendable {
    package let delta: WorktreeTopologyDelta
}

package enum RepositoryWorktreeReconciliationRejection: Equatable, Sendable {
    case repoNotFound(UUID)
    case worktreeNotFound(UUID)
    case worktreeRepoMismatch(
        worktreeId: UUID,
        expectedRepoId: UUID,
        actualRepoId: UUID
    )
    case duplicateWorktreeId(UUID)
    case duplicateWorktreeStableKey(String)
    case topologyRejected(RepositoryTopologyIdentityRejection)
}

package enum RepositoryWorktreeReconciliationResult: Equatable, Sendable {
    case accepted(RepositoryWorktreeReconciliationAcceptance)
    case rejected(RepositoryWorktreeReconciliationRejection)
}

package struct RepositoryReassociationAcceptance: Equatable, Sendable {
    let worktreeIds: Set<UUID>
    package let delta: WorktreeTopologyDelta
}

package enum RepositoryReassociationRejection: Equatable, Sendable {
    case duplicateRepositoryStableKey(String)
    case worktreeReconciliation(RepositoryWorktreeReconciliationRejection)
}

package enum RepositoryReassociationResult: Equatable, Sendable {
    case accepted(RepositoryReassociationAcceptance)
    case rejected(RepositoryReassociationRejection)
}
