import GRDB
import Testing

@testable import AgentStudio

@Suite("WorkspaceCoreGlobalTopologyMigrationTests")
struct WorkspaceCoreGlobalTopologyMigrationTests {
    @Test("forward migration installs global topology schema")
    func forwardMigrationInstallsGlobalTopologySchema() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()

        try WorkspaceCoreMigrations.migrate(databaseQueue)

        let schema = try databaseQueue.read { database in
            try CoreTopologySchemaSnapshot.read(from: database)
        }

        #expect(
            schema.columnDefinitionsByTable["watched_path"] == [
                "id|TEXT|0|<null>|1", "path|TEXT|1|<null>|0", "stable_key|TEXT|1|<null>|0",
                "added_at|REAL|1|<null>|0",
            ])
        #expect(
            schema.columnDefinitionsByTable["repo"] == [
                "id|TEXT|0|<null>|1", "name|TEXT|1|<null>|0", "repo_path|TEXT|1|<null>|0",
                "stable_key|TEXT|1|<null>|0", "created_at|REAL|1|<null>|0", "is_favorite|INTEGER|1|0|0",
                "note|TEXT|0|<null>|0",
            ])
        #expect(
            schema.columnDefinitionsByTable["worktree"] == [
                "id|TEXT|0|<null>|1", "repo_id|TEXT|1|<null>|0", "name|TEXT|1|<null>|0",
                "path|TEXT|1|<null>|0", "stable_key|TEXT|1|<null>|0",
                "is_main_worktree|INTEGER|1|<null>|0", "note|TEXT|0|<null>|0",
            ])
        #expect(
            schema.columnDefinitionsByTable["repo_tag"] == [
                "repo_id|TEXT|1|<null>|1", "tag|TEXT|1|<null>|2",
            ])
        #expect(schema.columnDefinitionsByTable["unavailable_repo"] == ["repo_id|TEXT|0|<null>|1"])
        #expect(schema.uniqueColumnSetsByTable["watched_path"] == Set([Set(["id"]), Set(["stable_key"])]))
        #expect(schema.uniqueColumnSetsByTable["repo"] == Set([Set(["id"]), Set(["stable_key"])]))
        #expect(schema.uniqueColumnSetsByTable["worktree"] == Set([Set(["id"]), Set(["stable_key"])]))
        #expect(schema.uniqueColumnSetsByTable["repo_tag"] == Set([Set(["repo_id", "tag"])]))
        #expect(schema.uniqueColumnSetsByTable["unavailable_repo"] == Set([Set(["repo_id"])]))
        #expect(schema.foreignKeysByTable["watched_path"]?.isEmpty == true)
        #expect(schema.foreignKeysByTable["repo"]?.isEmpty == true)
        #expect(schema.foreignKeysByTable["worktree"] == [.repoCascade(column: "repo_id")])
        #expect(schema.foreignKeysByTable["repo_tag"] == [.repoCascade(column: "repo_id")])
        #expect(schema.foreignKeysByTable["unavailable_repo"] == [.repoCascade(column: "repo_id")])
        #expect(
            schema.namedIndexColumns == [
                "idx_repo_tag_tag": ["tag"],
                "idx_worktree_repo_id": ["repo_id"],
            ])
        #expect(!schema.tableNames.contains("workspace_sqlite_snapshot_status"))
        #expect(!schema.tableNames.contains("legacy_workspace_import_status"))
        #expect(!schema.tableNames.contains { $0.hasSuffix("_global_new") })
        #expect(schema.obsoleteTopologyIndexNames.isEmpty)
        #expect(schema.obsoletePaneFacetTriggerNames.isEmpty)
    }

    @Test("global topology checks reject invalid stored values")
    func globalTopologyChecksRejectInvalidStoredValues() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceCoreMigrations.migrate(databaseQueue)

        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO repo(id, name, repo_path, stable_key, created_at)
                    VALUES ('repo-valid', 'Repository', '/repos/valid', 'repo-valid', 1)
                    """
            )
        }

        for invalidStatement in [
            """
            INSERT INTO repo(id, name, repo_path, stable_key, created_at, is_favorite)
            VALUES ('repo-invalid', 'Invalid', '/repos/invalid', 'repo-invalid', 1, 2)
            """,
            """
            INSERT INTO worktree(id, repo_id, name, path, stable_key, is_main_worktree)
            VALUES ('worktree-invalid', 'repo-valid', 'Invalid', '/repos/invalid', 'worktree-invalid', 2)
            """,
            "INSERT INTO repo_tag(repo_id, tag) VALUES ('repo-valid', ' padded ')",
            "INSERT INTO repo_tag(repo_id, tag) VALUES ('repo-valid', '\(String(repeating: "x", count: 65))')",
        ] {
            #expect(throws: DatabaseError.self) {
                try databaseQueue.write { database in
                    try database.execute(sql: invalidStatement)
                }
            }
        }
    }

    @Test("forward migration preserves topology identifiers values and pane lifecycle")
    func forwardMigrationPreservesTopologyIdentifiersValuesAndPaneLifecycle() throws {
        let databaseQueue = try legacyCoreDatabase()
        let fixture = CoreTopologyMigrationFixture()

        try databaseQueue.write { database in
            try fixture.insert(into: database)
        }
        let paneTableSQLBefore = try databaseQueue.read { database in
            try String.fetchOne(
                database,
                sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'pane'"
            )
        }
        let retainedPaneTriggersBefore = try databaseQueue.read { database in
            try paneTriggerDefinitions(database, excludingObsoleteTopologyTriggers: true)
        }

        try WorkspaceCoreMigrations.migrate(databaseQueue)

        let migrated = try databaseQueue.read { database in
            try MigratedCoreTopologySnapshot.read(from: database)
        }
        let paneTableSQLAfter = try databaseQueue.read { database in
            try String.fetchOne(
                database,
                sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'pane'"
            )
        }
        let retainedPaneTriggersAfter = try databaseQueue.read { database in
            try paneTriggerDefinitions(database, excludingObsoleteTopologyTriggers: false)
        }

        #expect(migrated.watchedPath == fixture.expectedWatchedPath)
        #expect(migrated.repository == fixture.expectedRepository)
        #expect(migrated.worktree == fixture.expectedWorktree)
        #expect(migrated.repositoryTag == fixture.expectedRepositoryTag)
        #expect(migrated.unavailableRepository == fixture.expectedUnavailableRepository)
        #expect(migrated.pane == fixture.expectedPane)
        #expect(paneTableSQLAfter == paneTableSQLBefore)
        #expect(retainedPaneTriggersAfter == retainedPaneTriggersBefore)
    }

    @Test("global stable key conflict rolls back the entire migration")
    func globalStableKeyConflictRollsBackEntireMigration() throws {
        for conflict in GlobalStableKeyConflict.allCases {
            let databaseQueue = try legacyCoreDatabase()
            let fixture = CoreTopologyMigrationFixture()
            try databaseQueue.write { database in
                try fixture.insert(into: database)
            }
            try WorkspaceCoreMigrations.migrator.migrate(
                databaseQueue,
                upTo: "012_background_active_unowned_layout_panes"
            )
            try databaseQueue.write { database in
                try conflict.insertConflictingRow(into: database, fixture: fixture)
            }
            let before = try databaseQueue.read { database in
                try LegacyCoreRollbackSnapshot.read(from: database)
            }

            #expect(throws: DatabaseError.self) {
                try WorkspaceCoreMigrations.migrate(databaseQueue)
            }

            let after = try databaseQueue.read { database in
                try LegacyCoreRollbackSnapshot.read(from: database)
            }
            #expect(after == before, "Migration must fully roll back a \(conflict) collision")
        }
    }

    @Test("deleting a workspace preserves global topology")
    func deletingWorkspacePreservesGlobalTopology() throws {
        let databaseQueue = try legacyCoreDatabase()
        let fixture = CoreTopologyMigrationFixture()

        try databaseQueue.write { database in
            try fixture.insert(into: database)
            try fixture.insertAdditionalTopologyRows(into: database)
        }
        try WorkspaceCoreMigrations.migrate(databaseQueue)
        let topologyBeforeDelete = try databaseQueue.read { database in
            try MigratedCoreTopologySnapshot.read(from: database).topologyValues
        }

        try databaseQueue.write { database in
            try database.execute(sql: "DELETE FROM workspace WHERE id = ?", arguments: [fixture.workspaceID])
        }

        let topologyAfterDelete = try databaseQueue.read { database in
            try MigratedCoreTopologySnapshot.read(from: database).topologyValues
        }
        #expect(topologyAfterDelete == topologyBeforeDelete)
    }

    @Test("two workspace panes may reference the same global topology")
    func twoWorkspacePanesMayReferenceSameGlobalTopology() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceCoreMigrations.migrate(databaseQueue)

        try databaseQueue.write { database in
            try insertWorkspace("workspace-one", into: database)
            try insertWorkspace("workspace-two", into: database)
            try database.execute(
                sql: """
                    INSERT INTO repo(id, name, repo_path, stable_key, created_at)
                    VALUES ('repo-one', 'Repository', '/repos/one', 'repo-one', 1)
                    """
            )
            try database.execute(
                sql: """
                    INSERT INTO worktree(id, repo_id, name, path, stable_key, is_main_worktree)
                    VALUES ('worktree-one', 'repo-one', 'main', '/repos/one', 'worktree-one', 1)
                    """
            )
            try insertPane(
                id: "pane-one",
                workspaceID: "workspace-one",
                repositoryID: "repo-one",
                worktreeID: "worktree-one",
                into: database
            )
            try insertPane(
                id: "pane-two",
                workspaceID: "workspace-two",
                repositoryID: "repo-one",
                worktreeID: "worktree-one",
                into: database
            )
        }

        let paneCount = try databaseQueue.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM pane WHERE facet_repo_id = 'repo-one'")
        }
        #expect(paneCount == 2)
    }

    private func legacyCoreDatabase() throws -> DatabaseQueue {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceCoreMigrations.migrator.migrate(
            databaseQueue,
            upTo: "011_add_repo_sidebar_metadata"
        )
        return databaseQueue
    }
}

private struct CoreTopologySchemaSnapshot {
    let tableNames: Set<String>
    let columnDefinitionsByTable: [String: [String]]
    let uniqueColumnSetsByTable: [String: Set<Set<String>>]
    let foreignKeysByTable: [String: [ForeignKeyContract]]
    let namedIndexColumns: [String: [String]]
    let obsoleteTopologyIndexNames: [String]
    let obsoletePaneFacetTriggerNames: [String]

    static func read(from database: Database) throws -> Self {
        let topologyTables = ["watched_path", "repo", "worktree", "repo_tag", "unavailable_repo"]
        let tableNames = try Set(
            String.fetchAll(
                database,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
            ))
        var columnDefinitionsByTable: [String: [String]] = [:]
        var uniqueColumnSetsByTable: [String: Set<Set<String>>] = [:]
        var foreignKeysByTable: [String: [ForeignKeyContract]] = [:]
        for tableName in topologyTables {
            let columnRows = try Row.fetchAll(database, sql: "PRAGMA table_info(\(tableName))")
            columnDefinitionsByTable[tableName] = columnRows.map { row in
                let name: String = row["name"]
                let type: String = row["type"]
                let notNull: Int = row["notnull"]
                let defaultValue: String? = row["dflt_value"]
                let primaryKeyPosition: Int = row["pk"]
                return "\(name)|\(type)|\(notNull)|\(defaultValue ?? "<null>")|\(primaryKeyPosition)"
            }

            let indexRows = try Row.fetchAll(database, sql: "PRAGMA index_list(\(tableName))")
            uniqueColumnSetsByTable[tableName] = try Set(
                indexRows.compactMap { row -> Set<String>? in
                    guard (row["unique"] as Int) == 1 else { return nil }
                    let indexName: String = row["name"]
                    return Set(try indexColumns(database, indexName: indexName))
                })
            foreignKeysByTable[tableName] = try Row.fetchAll(
                database,
                sql: "PRAGMA foreign_key_list(\(tableName))"
            ).map { row in
                ForeignKeyContract(
                    column: row["from"],
                    targetTable: row["table"],
                    targetColumn: row["to"],
                    onDelete: row["on_delete"]
                )
            }
        }
        let namedIndexRows = try Row.fetchAll(
            database,
            sql: """
                SELECT name
                FROM sqlite_master
                WHERE type = 'index'
                  AND tbl_name IN ('watched_path', 'repo', 'worktree', 'repo_tag', 'unavailable_repo')
                  AND sql IS NOT NULL
                ORDER BY name
                """
        )
        var namedIndexColumns: [String: [String]] = [:]
        for row in namedIndexRows {
            let indexName: String = row["name"]
            namedIndexColumns[indexName] = try indexColumns(database, indexName: indexName)
        }
        let obsoleteTopologyIndexNames = try String.fetchAll(
            database,
            sql: """
                SELECT name
                FROM sqlite_master
                WHERE type = 'index'
                  AND name IN (
                    'idx_repo_workspace_id',
                    'idx_worktree_workspace_id',
                    'idx_repo_tag_workspace_tag'
                  )
                ORDER BY name
                """
        )
        let obsoletePaneFacetTriggerNames = try String.fetchAll(
            database,
            sql: """
                SELECT name
                FROM sqlite_master
                WHERE type = 'trigger'
                  AND name IN (
                    'pane_facet_repo_matches_workspace',
                    'pane_facet_repo_update_matches_workspace',
                    'pane_facet_worktree_matches_workspace',
                    'pane_facet_worktree_update_matches_workspace'
                  )
                ORDER BY name
                """
        )
        return Self(
            tableNames: tableNames,
            columnDefinitionsByTable: columnDefinitionsByTable,
            uniqueColumnSetsByTable: uniqueColumnSetsByTable,
            foreignKeysByTable: foreignKeysByTable,
            namedIndexColumns: namedIndexColumns,
            obsoleteTopologyIndexNames: obsoleteTopologyIndexNames,
            obsoletePaneFacetTriggerNames: obsoletePaneFacetTriggerNames
        )
    }

    private static func indexColumns(_ database: Database, indexName: String) throws -> [String] {
        try Row.fetchAll(database, sql: "PRAGMA index_info(\(indexName))")
            .sorted { left, right in (left["seqno"] as Int) < (right["seqno"] as Int) }
            .map { row in row["name"] as String }
    }
}

private struct ForeignKeyContract: Equatable {
    let column: String
    let targetTable: String
    let targetColumn: String
    let onDelete: String

    static func repoCascade(column: String) -> Self {
        Self(column: column, targetTable: "repo", targetColumn: "id", onDelete: "CASCADE")
    }
}

private struct MigratedCoreTopologySnapshot {
    let watchedPath: [[String]]
    let repository: [[String]]
    let worktree: [[String]]
    let repositoryTag: [[String]]
    let unavailableRepository: [[String]]
    let pane: [[String]]

    var topologyValues: [[[String]]] {
        [watchedPath, repository, worktree, repositoryTag, unavailableRepository]
    }

    static func read(from database: Database) throws -> Self {
        Self(
            watchedPath: try requiredStringRows(
                database,
                sql: "SELECT id, path, stable_key, CAST(added_at AS TEXT) FROM watched_path ORDER BY id"
            ),
            repository: try requiredStringRows(
                database,
                sql: """
                    SELECT id, name, repo_path, stable_key, CAST(created_at AS TEXT),
                           CAST(is_favorite AS TEXT), COALESCE(note, '')
                    FROM repo
                    ORDER BY id
                    """
            ),
            worktree: try requiredStringRows(
                database,
                sql: """
                    SELECT id, repo_id, name, path, stable_key,
                           CAST(is_main_worktree AS TEXT), COALESCE(note, '')
                    FROM worktree
                    ORDER BY id
                    """
            ),
            repositoryTag: try requiredStringRows(
                database,
                sql: "SELECT repo_id, tag FROM repo_tag ORDER BY repo_id, tag"
            ),
            unavailableRepository: try requiredStringRows(
                database,
                sql: "SELECT repo_id FROM unavailable_repo ORDER BY repo_id"
            ),
            pane: try requiredStringRows(
                database,
                sql: """
                    SELECT pane.id, pane.workspace_id, pane.facet_repo_id, pane.facet_worktree_id,
                           pane.residency_kind, CAST(pane.pending_undo_expires_at AS TEXT),
                           pane.orphan_reason_kind, pane.orphan_worktree_path, pane.cwd,
                           pane_content_terminal.zmx_session_id
                    FROM pane
                    LEFT JOIN pane_content_terminal ON pane_content_terminal.pane_id = pane.id
                    ORDER BY pane.id
                    """
            )
        )
    }

    private static func requiredStringRows(_ database: Database, sql: String) throws -> [[String]] {
        try Row.fetchAll(database, sql: sql).map(databaseStringValues)
    }
}

private struct CoreTopologyMigrationFixture {
    let workspaceID = "workspace-one"
    let watchedPathID = "watched-path-one"
    let repositoryID = "repo-one"
    let worktreeID = "worktree-one"
    let paneID = "pane-one"

    var expectedWatchedPath: [[String]] {
        [[watchedPathID, "/watched", "watched-stable", "2.0"]]
    }

    var expectedRepository: [[String]] {
        [[repositoryID, "Repository", "/repos/repo-one", "repo-stable", "3.0", "1", "repository note"]]
    }

    var expectedWorktree: [[String]] {
        [[worktreeID, repositoryID, "main", "/repos/one", "worktree-stable", "1", "worktree note"]]
    }

    var expectedRepositoryTag: [[String]] {
        [[repositoryID, "important"]]
    }

    var expectedUnavailableRepository: [[String]] {
        [[repositoryID]]
    }

    var expectedPane: [[String]] {
        [
            [
                paneID, workspaceID, repositoryID, worktreeID, "pendingUndo", "900.0", "missingWorktree",
                "/missing/worktree", "/repos/one", "zmx-session-one",
            ]
        ]
    }

    func insert(into database: Database) throws {
        try insertWorkspace(workspaceID, into: database)
        try database.execute(
            sql: """
                INSERT INTO watched_path(id, workspace_id, path, stable_key, added_at)
                VALUES (?, ?, ?, ?, ?)
                """,
            arguments: [watchedPathID, workspaceID, "/watched", "watched-stable", 2.0]
        )
        try insertRepository(
            id: repositoryID,
            workspaceID: workspaceID,
            stableKey: "repo-stable",
            into: database
        )
        try database.execute(
            sql: "UPDATE repo SET is_favorite = 1, note = 'repository note' WHERE id = ?",
            arguments: [repositoryID]
        )
        try database.execute(
            sql: """
                INSERT INTO worktree(
                    id, workspace_id, repo_id, name, path, stable_key, is_main_worktree, note
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                worktreeID, workspaceID, repositoryID, "main", "/repos/one", "worktree-stable", 1,
                "worktree note",
            ]
        )
        try database.execute(
            sql: "INSERT INTO repo_tag(repo_id, workspace_id, tag) VALUES (?, ?, ?)",
            arguments: [repositoryID, workspaceID, "important"]
        )
        try database.execute(
            sql: "INSERT INTO unavailable_repo(workspace_id, repo_id) VALUES (?, ?)",
            arguments: [workspaceID, repositoryID]
        )
        try insertPane(
            id: paneID,
            workspaceID: workspaceID,
            repositoryID: repositoryID,
            worktreeID: worktreeID,
            into: database
        )
        try database.execute(
            sql: """
                INSERT INTO pane_content_terminal(pane_id, provider, lifetime, zmx_session_id)
                VALUES (?, 'zmx', 'persistent', 'zmx-session-one')
                """,
            arguments: [paneID]
        )
        try database.execute(
            sql: """
                    UPDATE pane
                    SET residency_kind = 'pendingUndo',
                        pending_undo_expires_at = 900,
                        orphan_reason_kind = 'missingWorktree',
                        orphan_worktree_path = '/missing/worktree'
                    WHERE id = ?
                """,
            arguments: [paneID]
        )
        try database.execute(
            sql: """
                INSERT INTO workspace_sqlite_snapshot_status(workspace_id, staged_at, completed_at)
                VALUES (?, 10, 10)
                """,
            arguments: [workspaceID]
        )
        try database.execute(
            sql: """
                INSERT INTO legacy_workspace_import_status(workspace_id, source_state_path)
                VALUES (?, '/legacy/state.json')
                """,
            arguments: [workspaceID]
        )
    }

    func insertAdditionalTopologyRows(into database: Database) throws {
        try database.execute(
            sql: """
                INSERT INTO watched_path(id, workspace_id, path, stable_key, added_at)
                VALUES ('watched-path-two', ?, '/watched/two', 'watched-stable-two', 4)
                """,
            arguments: [workspaceID]
        )
        try insertRepository(
            id: "repo-two",
            workspaceID: workspaceID,
            stableKey: "repo-stable-two",
            into: database
        )
        try database.execute(
            sql: """
                INSERT INTO worktree(
                    id, workspace_id, repo_id, name, path, stable_key, is_main_worktree
                )
                VALUES ('worktree-two', ?, 'repo-two', 'secondary', '/repos/two', 'worktree-stable-two', 0)
                """,
            arguments: [workspaceID]
        )
        try database.execute(
            sql: "INSERT INTO repo_tag(repo_id, workspace_id, tag) VALUES ('repo-two', ?, 'secondary')",
            arguments: [workspaceID]
        )
        try database.execute(
            sql: "INSERT INTO unavailable_repo(workspace_id, repo_id) VALUES (?, 'repo-two')",
            arguments: [workspaceID]
        )
    }
}

private enum GlobalStableKeyConflict: CaseIterable, CustomStringConvertible {
    case watchedPath
    case repository
    case worktree

    var description: String {
        switch self {
        case .watchedPath: "watched_path"
        case .repository: "repo"
        case .worktree: "worktree"
        }
    }

    func insertConflictingRow(
        into database: Database,
        fixture: CoreTopologyMigrationFixture
    ) throws {
        let workspaceID = "workspace-two"
        try insertWorkspace(workspaceID, into: database)
        switch self {
        case .watchedPath:
            try database.execute(
                sql: """
                    INSERT INTO watched_path(id, workspace_id, path, stable_key, added_at)
                    VALUES ('watched-path-conflict', ?, '/watched/conflict', 'watched-stable', 5)
                    """,
                arguments: [workspaceID]
            )
        case .repository:
            try insertRepository(
                id: "repo-conflict",
                workspaceID: workspaceID,
                stableKey: "repo-stable",
                into: database
            )
        case .worktree:
            try insertRepository(
                id: "repo-for-worktree-conflict",
                workspaceID: workspaceID,
                stableKey: "repo-for-worktree-conflict",
                into: database
            )
            try database.execute(
                sql: """
                    INSERT INTO worktree(
                        id, workspace_id, repo_id, name, path, stable_key, is_main_worktree
                    )
                    VALUES (?, ?, ?, 'conflict', '/worktree/conflict', ?, 0)
                    """,
                arguments: [
                    "worktree-conflict", workspaceID, "repo-for-worktree-conflict",
                    fixture.expectedWorktree[0][4],
                ]
            )
        }
    }
}

private struct LegacyCoreRollbackSnapshot: Equatable {
    let values: [[[String]]]

    static func read(from database: Database) throws -> Self {
        let queries = [
            "SELECT type, name, tbl_name, COALESCE(sql, '') FROM sqlite_master ORDER BY type, name",
            "SELECT * FROM watched_path ORDER BY id",
            "SELECT * FROM repo ORDER BY id",
            "SELECT * FROM worktree ORDER BY id",
            "SELECT * FROM repo_tag ORDER BY workspace_id, repo_id, tag",
            "SELECT * FROM unavailable_repo ORDER BY workspace_id, repo_id",
            "SELECT * FROM pane ORDER BY id",
            "SELECT * FROM pane_content_terminal ORDER BY pane_id",
            "SELECT * FROM workspace_sqlite_snapshot_status ORDER BY workspace_id",
            "SELECT * FROM legacy_workspace_import_status ORDER BY workspace_id",
            "SELECT identifier FROM grdb_migrations ORDER BY rowid",
        ]
        return Self(
            values: try queries.map { query in
                try Row.fetchAll(database, sql: query).map(databaseStringValues)
            })
    }
}

private func insertWorkspace(_ id: String, into database: Database) throws {
    try database.execute(
        sql: """
            INSERT INTO workspace(id, name, created_at, updated_at)
            VALUES (?, ?, ?, ?)
            """,
        arguments: [id, "Workspace", 1.0, 1.0]
    )
}

private func insertRepository(
    id: String,
    workspaceID: String,
    stableKey: String,
    into database: Database
) throws {
    try database.execute(
        sql: """
            INSERT INTO repo(id, workspace_id, name, repo_path, stable_key, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
        arguments: [id, workspaceID, "Repository", "/repos/\(id)", stableKey, 3.0]
    )
}

private func insertPane(
    id: String,
    workspaceID: String,
    repositoryID: String,
    worktreeID: String,
    into database: Database
) throws {
    try database.execute(
        sql: """
            INSERT INTO pane(
                id, workspace_id, content_type, execution_backend,
                facet_repo_id, facet_worktree_id, launch_directory, title, cwd,
                residency_kind, kind, created_at, updated_at
            )
            VALUES (?, ?, 'terminal', 'zmx', ?, ?, '/repos/one', 'Terminal', '/repos/one',
                    'active', 'leaf', 1, 1)
            """,
        arguments: [id, workspaceID, repositoryID, worktreeID]
    )
}

private func databaseStringValues(_ row: Row) -> [String] {
    row.map { _, databaseValue in
        String.fromDatabaseValue(databaseValue) ?? "<null>"
    }
}

private func paneTriggerDefinitions(
    _ database: Database,
    excludingObsoleteTopologyTriggers: Bool
) throws -> [[String]] {
    let obsoleteNames = [
        "pane_facet_repo_matches_workspace",
        "pane_facet_repo_update_matches_workspace",
        "pane_facet_worktree_matches_workspace",
        "pane_facet_worktree_update_matches_workspace",
    ]
    let exclusion =
        excludingObsoleteTopologyTriggers
        ? "AND name NOT IN (\(obsoleteNames.map { _ in "?" }.joined(separator: ", ")))"
        : ""
    return try Row.fetchAll(
        database,
        sql: """
            SELECT name, sql
            FROM sqlite_master
            WHERE type = 'trigger'
              AND tbl_name = 'pane'
              \(exclusion)
            ORDER BY name
            """,
        arguments: excludingObsoleteTopologyTriggers ? StatementArguments(obsoleteNames) : StatementArguments()
    ).map(databaseStringValues)
}
