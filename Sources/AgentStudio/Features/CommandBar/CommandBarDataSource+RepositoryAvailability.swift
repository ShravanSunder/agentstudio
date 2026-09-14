import AgentStudioCore

@MainActor
extension CommandBarDataSource {
    static func availableRepositories(store: WorkspaceStore) -> [Repo] {
        store.repositoryTopologyAtom.repositoryIdsInOrder.compactMap { repositoryID in
            guard let repository = store.repositoryTopologyAtom.repo(repositoryID) else { return nil }
            return availableRepository(repository, store: store)
        }
    }

    static func availableRepository(_ repository: Repo, store: WorkspaceStore) -> Repo? {
        let topology = store.repositoryTopologyAtom
        guard let current = topology.repo(repository.id), !topology.isRepoUnavailable(repository.id) else { return nil }
        var available = current
        available.worktrees = current.worktrees.filter { !topology.isWorktreeUnavailable($0.id) }
        return available.worktrees.isEmpty ? nil : available
    }
}
