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
        case .loaded(let snapshot):
            atom.publishAuthoritative(snapshot)
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
