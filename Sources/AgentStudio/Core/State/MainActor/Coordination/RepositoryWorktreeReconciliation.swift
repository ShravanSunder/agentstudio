import Foundation

struct RemovedWorktreeEntry: Sendable, Equatable {
    let id: UUID
    let path: URL
}

struct WorktreeTopologyDelta: Sendable, Equatable {
    let repoId: UUID
    let addedWorktreeIds: [UUID]
    let removedWorktrees: [RemovedWorktreeEntry]
    let preservedWorktreeIds: [UUID]
    let didChange: Bool
    let traceId: UUID?
}

struct RepositoryScannedMainWorktree: Equatable, Sendable {
    let name: String
    let path: URL
}

struct RepositoryScannedLinkedWorktree: Equatable, Sendable {
    let name: String
    let path: URL
}

struct RepositoryScannedWorktrees: Equatable, Sendable {
    let main: RepositoryScannedMainWorktree
    let linked: [RepositoryScannedLinkedWorktree]
}

struct RepositoryWorktreeReconciliationAcceptance: Equatable, Sendable {
    let delta: WorktreeTopologyDelta
}

enum RepositoryWorktreeReconciliationRejection: Equatable, Sendable {
    case repoNotFound(UUID)
    case worktreeRepoMismatch(
        worktreeId: UUID,
        expectedRepoId: UUID,
        actualRepoId: UUID
    )
    case duplicateWorktreeId(UUID)
    case duplicateWorktreeStableKey(String)
}

enum RepositoryWorktreeReconciliationResult: Equatable, Sendable {
    case accepted(RepositoryWorktreeReconciliationAcceptance)
    case rejected(RepositoryWorktreeReconciliationRejection)
}

struct RepositoryReassociationAcceptance: Equatable, Sendable {
    let worktreeIds: Set<UUID>
    let delta: WorktreeTopologyDelta
}

enum RepositoryReassociationRejection: Equatable, Sendable {
    case duplicateRepositoryStableKey(String)
    case worktreeReconciliation(RepositoryWorktreeReconciliationRejection)
}

enum RepositoryReassociationResult: Equatable, Sendable {
    case accepted(RepositoryReassociationAcceptance)
    case rejected(RepositoryReassociationRejection)
}
