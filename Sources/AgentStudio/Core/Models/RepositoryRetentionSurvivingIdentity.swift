import Foundation

package struct RepositoryRetentionSurvivingIdentity: Sendable {
    package let repositoryIDs: Set<UUID>
    package let worktreeIDs: Set<UUID>
    package let repositoryKeys: Set<String>
    package let worktreeKeys: Set<String>
    package let worktreeRepositoryIDs: [UUID: UUID]

    package init(
        repositoryIDs: Set<UUID>, worktreeIDs: Set<UUID>, repositoryKeys: Set<String>, worktreeKeys: Set<String>,
        worktreeRepositoryIDs: [UUID: UUID] = [:]
    ) {
        self.repositoryIDs = repositoryIDs
        self.worktreeIDs = worktreeIDs
        self.repositoryKeys = repositoryKeys
        self.worktreeKeys = worktreeKeys
        self.worktreeRepositoryIDs = worktreeRepositoryIDs
    }
}

package enum RepositoryRetentionLocalCleanupResult: Equatable, Sendable {
    case complete
    case progress
    case unavailable
}
