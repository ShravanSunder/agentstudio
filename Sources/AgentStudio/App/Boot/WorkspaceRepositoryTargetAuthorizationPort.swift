import Foundation

@MainActor
final class WorkspaceRepositoryTargetAuthorizationPort: WorkspaceRepositoryTargetAuthorizing {
    private let repositoryTopology: RepositoryTopologyAtom

    init(repositoryTopology: RepositoryTopologyAtom) {
        self.repositoryTopology = repositoryTopology
    }

    func containsRepository(id: UUID) -> Bool {
        repositoryTopology.repo(id) != nil
    }
}
