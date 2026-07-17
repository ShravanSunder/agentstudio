import Foundation

@MainActor
final class WorkspaceRepositoryTargetAuthorizationPort: WorkspaceRepositoryTargetAuthorizing {
    private let repositoryExists: @MainActor (UUID) -> Bool

    init(repositoryExists: @escaping @MainActor (UUID) -> Bool) {
        self.repositoryExists = repositoryExists
    }

    func containsRepository(id: UUID) -> Bool {
        repositoryExists(id)
    }
}
