import Foundation

/// Accepted same-location transition; ordinary snapshot saves carry no ownership authority.
package struct RepositoryWorktreeReparenting: Equatable, Sendable {
    package let worktreeID: UUID
    package let expectedRepositoryID: UUID
    package let repositoryID: UUID

    package init(worktreeID: UUID, expectedRepositoryID: UUID, repositoryID: UUID) {
        self.worktreeID = worktreeID
        self.expectedRepositoryID = expectedRepositoryID
        self.repositoryID = repositoryID
    }
}
