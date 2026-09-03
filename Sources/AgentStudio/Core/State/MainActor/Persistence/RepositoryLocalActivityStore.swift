@MainActor
package final class RepositoryLocalActivityStore {
    private let atom: RepositoryLocalActivityAtom
    private let sqliteDatastore: WorkspaceSQLiteDatastore
    private var currentSessionAuthoritativeRepositoryStableKeys: Set<String> = []
    private var authorityRevisionByRepositoryStableKey: [String: UInt64] = [:]

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
        currentSessionAuthoritativeRepositoryStableKeys.removeAll(keepingCapacity: true)
        authorityRevisionByRepositoryStableKey.removeAll(keepingCapacity: true)
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
        let authorityRevisionAtCommitStart = Dictionary(
            uniqueKeysWithValues: commit.repositoryUpdates.map { update in
                (
                    update.repositoryStableKey,
                    authorityRevisionByRepositoryStableKey[update.repositoryStableKey] ?? 0
                )
            }
        )
        let acceptedSnapshot = try await sqliteDatastore.commitRepositoryLocalActivity(commit)
        currentSessionAuthoritativeRepositoryStableKeys.formUnion(
            commit.repositoryUpdates.compactMap { update in
                let repositoryStableKey = update.repositoryStableKey
                guard
                    authorityRevisionByRepositoryStableKey[repositoryStableKey] ?? 0
                        == authorityRevisionAtCommitStart[repositoryStableKey]
                else { return nil }
                return repositoryStableKey
            }
        )
        let currentSessionSnapshot = RepositoryLocalActivitySnapshot(
            activityByRepositoryStableKey: acceptedSnapshot.activityByRepositoryStableKey.filter {
                currentSessionAuthoritativeRepositoryStableKeys.contains($0.key)
            },
            cursorByVolumeIdentifier: acceptedSnapshot.cursorByVolumeIdentifier
        )
        atom.publishAuthoritative(currentSessionSnapshot)
        isHydrated = true
        return currentSessionSnapshot
    }

    package func revokeCurrentSessionAuthority(
        for repositoryStableKeys: Set<String>
    ) {
        guard !repositoryStableKeys.isEmpty else { return }
        for repositoryStableKey in repositoryStableKeys {
            authorityRevisionByRepositoryStableKey[repositoryStableKey, default: 0] &+= 1
        }
        let revokedAuthoritativeRepositoryStableKeys =
            currentSessionAuthoritativeRepositoryStableKeys.intersection(repositoryStableKeys)
        guard !revokedAuthoritativeRepositoryStableKeys.isEmpty else { return }
        currentSessionAuthoritativeRepositoryStableKeys.subtract(
            revokedAuthoritativeRepositoryStableKeys
        )
        let retainedActivity = atom.snapshot().filter {
            currentSessionAuthoritativeRepositoryStableKeys.contains($0.key)
        }
        atom.publishAuthoritative(
            RepositoryLocalActivitySnapshot(
                activityByRepositoryStableKey: retainedActivity,
                cursorByVolumeIdentifier: [:]
            )
        )
    }
}
