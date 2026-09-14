import Foundation

package enum RepositoryTopologyAbsenceValidationError: Error, Equatable, Sendable {
    case repositoryOwnerMissing(UUID)
    case repositoryRecordUsesWorktreeOwner(UUID)
    case repositoryRecordDoesNotMatchUnavailableState(UUID)
    case worktreeOwnerMissing(UUID)
    case worktreeRecordUsesRepositoryOwner(UUID)
}

/// One canonical value owns absence metadata; ID sets are read-only projections.
package struct RepositoryTopologyAbsenceRecords: Equatable, Sendable {
    package var repositories: [UUID: RepositoryLocationAbsence]
    package var worktrees: [UUID: RepositoryLocationAbsence]

    package init(
        repositories: [UUID: RepositoryLocationAbsence] = [:],
        worktrees: [UUID: RepositoryLocationAbsence] = [:]
    ) {
        self.repositories = repositories
        self.worktrees = worktrees
    }

    package var unavailableRepositoryIDs: Set<UUID> { Set(repositories.keys) }
    package var unavailableWorktreeIDs: Set<UUID> { Set(worktrees.keys) }

    package func validationError(
        repositoryIDs: Set<UUID>,
        unavailableRepositoryIDs: Set<UUID>,
        worktreeIDs: Set<UUID>
    ) -> RepositoryTopologyAbsenceValidationError? {
        for repositoryID in repositories.keys {
            guard repositoryIDs.contains(repositoryID) else {
                return worktreeIDs.contains(repositoryID)
                    ? .repositoryRecordUsesWorktreeOwner(repositoryID)
                    : .repositoryOwnerMissing(repositoryID)
            }
            guard unavailableRepositoryIDs.contains(repositoryID) else {
                return .repositoryRecordDoesNotMatchUnavailableState(repositoryID)
            }
        }
        for worktreeID in worktrees.keys where !worktreeIDs.contains(worktreeID) {
            return repositoryIDs.contains(worktreeID)
                ? .worktreeRecordUsesRepositoryOwner(worktreeID)
                : .worktreeOwnerMissing(worktreeID)
        }
        return nil
    }

    package func addingLegacyUnavailableRepositories(_ unavailableRepositoryIDs: Set<UUID>) -> Self {
        var normalized = self
        for repositoryID in unavailableRepositoryIDs where normalized.repositories[repositoryID] == nil {
            normalized.repositories[repositoryID] = .unconfirmed
        }
        return normalized
    }

    package func retaining(
        unavailableRepositoryIDs: Set<UUID>,
        existingWorktreeIDs: Set<UUID>
    ) -> Self {
        Self(
            repositories: Dictionary(
                uniqueKeysWithValues: unavailableRepositoryIDs.map { ($0, repositories[$0] ?? .unconfirmed) }
            ),
            worktrees: worktrees.filter { existingWorktreeIDs.contains($0.key) }
        )
    }
}
