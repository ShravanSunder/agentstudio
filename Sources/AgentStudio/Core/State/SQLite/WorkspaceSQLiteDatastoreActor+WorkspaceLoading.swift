extension WorkspaceSQLiteDatastoreActor {
    func loadWorkspaceSnapshot() async -> LoadResult {
        switch await loadAuthoritativeCoreSnapshot() {
        case .loaded(let snapshot):
            return .loaded(snapshot.workspace)
        case .uninitialized:
            return .uninitialized
        case .unavailable(let failure):
            return .unavailable(failure)
        }
    }
}
