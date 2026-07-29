import Foundation

package struct RemovedWorktreeEntry: Sendable, Equatable {
    package let id: UUID
    package let path: URL
}

package struct WorktreeTopologyDelta: Sendable, Equatable {
    let repoId: UUID
    let addedWorktreeIds: [UUID]
    package let removedWorktrees: [RemovedWorktreeEntry]
    let preservedWorktreeIds: [UUID]
    package let didChange: Bool
    let traceId: UUID?
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
    case worktreeRepoMismatch(
        worktreeId: UUID,
        expectedRepoId: UUID,
        actualRepoId: UUID
    )
    case duplicateWorktreeId(UUID)
    case duplicateWorktreeStableKey(String)
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
