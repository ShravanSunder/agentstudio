import Foundation

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
