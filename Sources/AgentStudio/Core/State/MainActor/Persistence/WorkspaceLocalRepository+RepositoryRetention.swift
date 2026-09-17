import Foundation
import GRDB

extension WorkspaceLocalRepository {
    /// Local-only orphanhood is reconstructible from core IDs; historical tables and cursors are deliberately excluded.
    func pruneOrphanedRepositoryState(surviving: RepositoryRetentionSurvivingIdentity, limit: Int) throws -> Int {
        guard limit > 0 else { return 0 }
        let repositoryIDs = try retentionKeysJSON(Set(surviving.repositoryIDs.map(\.uuidString)))
        let worktreeOwners = try retentionJSON(
            Dictionary(
                uniqueKeysWithValues: surviving.worktreeRepositoryIDs.map { ($0.key.uuidString, $0.value.uuidString) })
        )
        let repositoryKeys = try retentionKeysJSON(surviving.repositoryKeys)
        let worktreeKeys = try retentionKeysJSON(surviving.worktreeKeys)
        return try databaseWriter.write { database in
            var remaining = limit
            let statements: [(String, [String])] = [
                ("cache_repo_enrichment WHERE repo_id NOT IN (SELECT value FROM json_each(?))", [repositoryIDs]),
                (
                    "cache_worktree_enrichment WHERE NOT EXISTS (SELECT 1 FROM json_each(?) AS owner WHERE owner.key = worktree_id AND owner.value = repo_id)",
                    [worktreeOwners]
                ),
                (
                    "local_entity_recency WHERE (entity_kind = 'repository' AND entity_key NOT IN (SELECT value FROM json_each(?))) OR (entity_kind = 'worktree' AND entity_key NOT IN (SELECT value FROM json_each(?)))",
                    [repositoryKeys, worktreeKeys]
                ),
                (
                    "local_repository_activity WHERE owned_promotion_unsettled = 0 AND repository_stable_key NOT IN (SELECT value FROM json_each(?))",
                    [repositoryKeys]
                ),
            ]
            for (selection, keys) in statements where remaining > 0 {
                let table = String(selection.prefix { $0 != " " })
                var arguments = StatementArguments(keys)
                arguments += [remaining]
                try database.execute(
                    sql: "DELETE FROM \(table) WHERE rowid IN (SELECT rowid FROM \(selection) LIMIT ?)",
                    arguments: arguments
                )
                remaining -= database.changesCount
            }
            return limit - remaining
        }
    }

    func unsettledRepositoryRetentionKeys() throws -> Set<String> {
        try databaseWriter.read { database in
            Set(
                try String.fetchAll(
                    database,
                    sql:
                        "SELECT repository_stable_key FROM local_repository_activity WHERE owned_promotion_unsettled = 1"
                ))
        }
    }
}

private func retentionKeysJSON(_ keys: Set<String>) throws -> String {
    try retentionJSON(keys.sorted())
}

private func retentionJSON<Value: Encodable>(_ value: Value) throws -> String {
    guard let encoded = String(bytes: try JSONEncoder().encode(value), encoding: .utf8) else {
        throw CocoaError(.fileWriteInapplicableStringEncoding)
    }
    return encoded
}
