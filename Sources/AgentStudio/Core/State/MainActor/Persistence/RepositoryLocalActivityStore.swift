@MainActor
package final class RepositoryLocalActivityStore {
    private let atom: RepositoryLocalActivityAtom
    private let sqliteDatastore: WorkspaceSQLiteDatastore

    package private(set) var isHydrated = false

    package init(
        atom: RepositoryLocalActivityAtom,
        sqliteDatastore: WorkspaceSQLiteDatastore
    ) {
        self.atom = atom
        self.sqliteDatastore = sqliteDatastore
    }

    package func restoreAsync() async {
        guard !isHydrated else { return }
        switch await sqliteDatastore.loadRepositoryLocalActivity() {
        case .loaded:
            // Persisted activity survives restart, but PR1 does not replay the
            // FSEvents gap. Keep classification unknown until the first live
            // activity checkpoint restarts coverage and commits a current
            // authoritative snapshot.
            atom.publishUnavailable()
        case .unavailable:
            atom.publishUnavailable()
        }
        isHydrated = true
    }

    @discardableResult
    package func commitAsync(
        _ commit: RepositoryLocalActivityCommit
    ) async throws -> RepositoryLocalActivitySnapshot {
        let acceptedSnapshot = try await sqliteDatastore.commitRepositoryLocalActivity(commit)
        atom.publishAuthoritative(acceptedSnapshot)
        isHydrated = true
        return acceptedSnapshot
    }
}
