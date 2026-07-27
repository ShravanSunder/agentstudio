import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("WorkspaceLocalSchemaContractTests")
struct WorkspaceLocalSchemaContractTests {
    @Test("local storage tokens match live core enum vocabularies")
    func localStorageTokensMatchLiveCoreEnumVocabularies() {
        let sidebarSurfaceStorageValues = Set(
            SidebarSurface.allCases.map { SQLiteLocalUXStorage.storageValue(for: $0) }
        )
        let recentTargetKindStorageValues = Set(
            RecentWorkspaceTarget.Kind.allCases.map { SQLiteLocalUXStorage.storageValue(for: $0) }
        )

        #expect(sidebarSurfaceStorageValues == Set(["repos", "inbox"]))
        #expect(recentTargetKindStorageValues == Set(["worktree", "cwdOnly"]))
    }

    @Test("notification claim lane storage matches mergeable lane vocabulary")
    func notificationClaimLaneStorageMatchesMergeableLaneVocabulary() {
        let claimLaneStorageValues = Set(InboxNotificationClaimLane.allCases.map(\.rawValue))
        let mergeableLaneStorageValues = Set(
            InboxNotificationClaimLane.allCases
                .filter(\.canMergeWithinActivitySession)
                .map(\.rawValue)
        )

        #expect(claimLaneStorageValues == SQLiteInboxNotificationClaimStorage.allLaneStorageValues)
        #expect(mergeableLaneStorageValues == SQLiteInboxNotificationClaimStorage.mergeableLaneStorageValues)
    }

    @Test("malformed recent targets disappear and valid typed targets survive")
    func malformedRecentTargetsDisappearAndValidTypedTargetsSurvive() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let workspaceId = UUID()
        let repository = WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: databaseQueue)
        let validTarget = RecentWorkspaceTarget.forCwd(
            URL(fileURLWithPath: "/tmp/valid"),
            lastOpenedAt: Date(timeIntervalSince1970: 2)
        )
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()
        let worktreePath = URL(fileURLWithPath: "/tmp/valid-worktree")
        let validWorktreeTarget = RecentWorkspaceTarget.forWorktree(
            path: worktreePath,
            worktree: Worktree(id: worktreeId, repoId: repoId, name: "Valid", path: worktreePath),
            repo: Repo(id: repoId, name: "Repo", repoPath: worktreePath),
            lastOpenedAt: Date(timeIntervalSince1970: 3)
        )
        try repository.replaceRecentTargets(
            [validTarget, validWorktreeTarget],
            updatedAt: Date(timeIntervalSince1970: 3)
        )
        let malformedRows: [MalformedRecentTargetRow] = [
            .init(id: "unsupported-kind", repoId: nil, worktreeId: nil, kind: "futureKind"),
            .init(id: "worktree-neither", repoId: nil, worktreeId: nil, kind: "worktree"),
            .init(id: "worktree-missing-repo", repoId: nil, worktreeId: worktreeId.uuidString, kind: "worktree"),
            .init(id: "worktree-missing-worktree", repoId: repoId.uuidString, worktreeId: nil, kind: "worktree"),
            .init(id: "cwd-with-repo", repoId: repoId.uuidString, worktreeId: nil, kind: "cwdOnly"),
            .init(id: "cwd-with-worktree", repoId: nil, worktreeId: worktreeId.uuidString, kind: "cwdOnly"),
            .init(
                id: "cwd-with-both",
                repoId: repoId.uuidString,
                worktreeId: worktreeId.uuidString,
                kind: "cwdOnly"
            ),
            .init(
                id: "malformed-repo-id",
                repoId: "not-a-uuid",
                worktreeId: worktreeId.uuidString,
                kind: "worktree"
            ),
            .init(
                id: "malformed-worktree-id",
                repoId: repoId.uuidString,
                worktreeId: "not-a-uuid",
                kind: "worktree"
            ),
        ]
        try databaseQueue.write { database in
            for row in malformedRows {
                try database.execute(
                    sql: """
                        INSERT INTO local_recent_workspace_target(
                            workspace_id, id, path, display_title, subtitle,
                            repo_id, worktree_id, kind, last_opened_at
                        ) VALUES (?, ?, '/tmp/malformed', 'Malformed', '', ?, ?, ?, 1)
                        """,
                    arguments: [workspaceId.uuidString, row.id, row.repoId, row.worktreeId, row.kind]
                )
            }
        }

        #expect(try repository.fetchRecentTargets() == [validWorktreeTarget, validTarget])
    }

    @Test("typed preferences round trip and malformed rows use defaults")
    func typedPreferencesRoundTripAndMalformedRowsUseDefaults() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let workspaceId = UUID()
        let repository = WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: databaseQueue)
        let repoPreferences = WorkspaceLocalRepository.RepoExplorerPreferencesRecord(
            groupingMode: .pane,
            sortOrder: .descending,
            visibilityMode: .favoritesOnly
        )
        try repository.replaceRepoExplorerPreferences(repoPreferences, updatedAt: Date(timeIntervalSince1970: 1))
        #expect(try repository.fetchRepoExplorerPreferences() == repoPreferences)

        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    UPDATE local_repo_explorer_preferences
                    SET grouping_mode = 'unsupported'
                    WHERE workspace_id = ?
                    """,
                arguments: [workspaceId.uuidString]
            )
        }
        #expect(try repository.fetchRepoExplorerPreferences() == .default)
    }

    @Test("local lookup indexes exactly match the target contract")
    func localLookupIndexesExactlyMatchTheTargetContract() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)

        let indexNames = try databaseQueue.read { database in
            try Set(
                String.fetchAll(
                    database,
                    sql: """
                        SELECT name
                        FROM sqlite_master
                        WHERE type = 'index'
                        """
                )
            )
        }

        let expectedIndexNames: Set<String> = [
            "idx_local_tab_cursor_workspace",
            "idx_local_arrangement_cursor_workspace",
            "idx_local_drawer_cursor_workspace",
            "idx_local_drawer_one_expanded_per_workspace",
            "idx_local_arrangement_drawer_cursor_workspace",
            "idx_local_recent_target_workspace_time",
            "idx_notification_workspace_timestamp",
            "idx_notification_workspace_pane",
            "idx_notification_workspace_tab",
            "idx_notification_workspace_repo",
            "idx_notification_workspace_worktree",
            "idx_notification_claim_exact",
            "idx_notification_claim_session",
            "idx_cache_worktree_repo",
            "idx_cache_pull_request_repo",
        ]

        let productIndexNames = Set(indexNames.filter { !$0.hasPrefix("sqlite_autoindex_") })
        #expect(productIndexNames == expectedIndexNames)
    }

    @Test("local window recent target and notification tables match the exact structural contract")
    func localWindowRecentTargetAndNotificationTablesMatchExactStructuralContract() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)

        try assertLocalSchemaStructuralContract(in: databaseQueue)
    }
}

private struct MalformedRecentTargetRow {
    let id: String
    let repoId: String?
    let worktreeId: String?
    let kind: String
}

private struct LocalSchemaForeignKeyContract: Equatable {
    let sourceTable: String
    let targetTable: String
    let sourceColumn: String
    let targetColumn: String
    let onDelete: String
}

private let localSchemaExpectedColumns: [String: [(String, Int)]] = [
    "local_workspace_cursor": [
        ("workspace_id", 1), ("active_tab_id", 0), ("updated_at", 0),
    ],
    "local_tab_cursor": [
        ("workspace_id", 1), ("tab_id", 2), ("active_arrangement_id", 0), ("updated_at", 0),
    ],
    "local_arrangement_cursor": [
        ("workspace_id", 1), ("arrangement_id", 2), ("active_pane_id", 0), ("updated_at", 0),
    ],
    "local_drawer_cursor": [
        ("workspace_id", 1), ("drawer_id", 2), ("is_expanded", 0), ("updated_at", 0),
    ],
    "local_arrangement_drawer_cursor": [
        ("workspace_id", 1), ("arrangement_id", 2), ("drawer_id", 3),
        ("active_child_id", 0), ("updated_at", 0),
    ],
    "local_window_state": [
        ("window_id", 1), ("window_role", 0), ("sidebar_width", 0),
        ("window_frame_json", 0), ("filter_text", 0), ("is_filter_visible", 0),
        ("sidebar_collapsed", 0), ("sidebar_surface", 0), ("updated_at", 0),
    ],
    "local_window_sidebar_expanded_group": [
        ("window_id", 1), ("group_key", 2),
    ],
    "local_recent_workspace_target": [
        ("workspace_id", 1), ("id", 2), ("path", 0), ("display_title", 0),
        ("subtitle", 0), ("repo_id", 0), ("worktree_id", 0), ("kind", 0),
        ("last_opened_at", 0),
    ],
    "local_notification_inbox_collapsed_group": [
        ("workspace_id", 1), ("group_key", 2),
    ],
    "local_notification_inbox_item": [
        ("workspace_id", 1), ("id", 2), ("timestamp", 0), ("kind", 0),
        ("title", 0), ("body", 0), ("source_kind", 0), ("pane_id", 0),
        ("tab_id", 0), ("tab_display_label", 0), ("tab_ordinal", 0),
        ("repo_id", 0), ("repo_name", 0), ("worktree_id", 0),
        ("worktree_name", 0), ("branch_name", 0), ("pane_display_label", 0),
        ("pane_ordinal", 0), ("pane_role", 0), ("parent_pane_id", 0),
        ("parent_pane_display_label", 0), ("parent_pane_ordinal", 0),
        ("drawer_ordinal", 0), ("runtime_display_label", 0),
        ("activity_burst_window_id", 0), ("activity_session_id", 0),
        ("activity_event_count", 0), ("activity_rows_added", 0),
        ("activity_threshold_rows", 0), ("activity_latest_rows", 0),
        ("claim_pane_id", 0), ("claim_lane", 0), ("claim_semantic", 0),
        ("claim_session_id", 0), ("is_read", 0),
        ("is_dismissed_from_pane_inbox", 0),
    ],
    "local_editor_preferences": [
        ("workspace_id", 1), ("bookmarked_editor_id", 0), ("updated_at", 0),
    ],
    "local_repo_explorer_preferences": [
        ("workspace_id", 1), ("grouping_mode", 0), ("sort_order", 0),
        ("visibility_mode", 0), ("updated_at", 0),
    ],
    "local_inbox_notification_preferences": [
        ("workspace_id", 1), ("grouping", 0), ("sort_order", 0), ("bell_enabled", 0),
        ("global_content_mode", 0), ("global_row_state_filter", 0),
        ("pane_content_mode", 0), ("pane_row_state_filter", 0), ("updated_at", 0),
    ],
    "cache_metadata": [
        ("singleton_id", 1), ("source_revision", 0), ("last_rebuilt_at", 0),
    ],
    "cache_repo_enrichment": [
        ("repo_id", 1), ("state", 0), ("origin", 0), ("upstream", 0),
        ("group_key", 0), ("remote_slug", 0), ("organization_name", 0),
        ("display_name", 0), ("updated_at", 0), ("payload_json", 0),
    ],
    "cache_worktree_enrichment": [
        ("worktree_id", 1), ("repo_id", 0), ("branch", 0), ("is_main_worktree", 0),
        ("updated_at", 0), ("payload_json", 0),
    ],
    "cache_pull_request_count": [
        ("worktree_id", 1), ("repo_id", 0), ("count", 0), ("updated_at", 0),
    ],
]

private let localSchemaExpectedTypes: [String: [String]] = [
    "local_workspace_cursor": ["TEXT", "TEXT", "REAL"],
    "local_tab_cursor": ["TEXT", "TEXT", "TEXT", "REAL"],
    "local_arrangement_cursor": ["TEXT", "TEXT", "TEXT", "REAL"],
    "local_drawer_cursor": ["TEXT", "TEXT", "INTEGER", "REAL"],
    "local_arrangement_drawer_cursor": ["TEXT", "TEXT", "TEXT", "TEXT", "REAL"],
    "local_window_state": ["TEXT", "TEXT", "REAL", "TEXT", "TEXT", "INTEGER", "INTEGER", "TEXT", "REAL"],
    "local_window_sidebar_expanded_group": ["TEXT", "TEXT"],
    "local_recent_workspace_target": ["TEXT", "TEXT", "TEXT", "TEXT", "TEXT", "TEXT", "TEXT", "TEXT", "REAL"],
    "local_notification_inbox_collapsed_group": ["TEXT", "TEXT"],
    "local_notification_inbox_item": [
        "TEXT", "TEXT", "REAL", "TEXT", "TEXT", "TEXT", "TEXT", "TEXT", "TEXT", "TEXT", "INTEGER",
        "TEXT", "TEXT", "TEXT", "TEXT", "TEXT", "TEXT", "INTEGER", "TEXT", "TEXT", "TEXT", "INTEGER",
        "INTEGER", "TEXT", "TEXT", "TEXT", "INTEGER", "INTEGER", "INTEGER", "INTEGER", "TEXT", "TEXT",
        "TEXT", "TEXT", "INTEGER", "INTEGER",
    ],
    "local_editor_preferences": ["TEXT", "TEXT", "REAL"],
    "local_repo_explorer_preferences": ["TEXT", "TEXT", "TEXT", "TEXT", "REAL"],
    "local_inbox_notification_preferences": [
        "TEXT", "TEXT", "TEXT", "INTEGER", "TEXT", "TEXT", "TEXT", "TEXT", "REAL",
    ],
    "cache_metadata": ["INTEGER", "INTEGER", "REAL"],
    "cache_repo_enrichment": ["TEXT", "TEXT", "TEXT", "TEXT", "TEXT", "TEXT", "TEXT", "TEXT", "REAL", "TEXT"],
    "cache_worktree_enrichment": ["TEXT", "TEXT", "TEXT", "INTEGER", "REAL", "TEXT"],
    "cache_pull_request_count": ["TEXT", "TEXT", "INTEGER", "REAL"],
]

private let localSchemaExpectedNotNullColumns: [String: Set<String>] = [
    "local_workspace_cursor": ["updated_at"],
    "local_tab_cursor": ["workspace_id", "tab_id", "updated_at"],
    "local_arrangement_cursor": ["workspace_id", "arrangement_id", "updated_at"],
    "local_drawer_cursor": ["workspace_id", "drawer_id", "is_expanded", "updated_at"],
    "local_arrangement_drawer_cursor": ["workspace_id", "arrangement_id", "drawer_id", "updated_at"],
    "local_window_state": [
        "window_role", "sidebar_width", "filter_text", "is_filter_visible", "sidebar_collapsed",
        "sidebar_surface", "updated_at",
    ],
    "local_window_sidebar_expanded_group": ["window_id", "group_key"],
    "local_recent_workspace_target": [
        "workspace_id", "id", "path", "display_title", "subtitle", "kind", "last_opened_at",
    ],
    "local_notification_inbox_collapsed_group": ["workspace_id", "group_key"],
    "local_notification_inbox_item": [
        "workspace_id", "id", "timestamp", "kind", "title", "source_kind", "is_read",
        "is_dismissed_from_pane_inbox",
    ],
    "local_editor_preferences": ["updated_at"],
    "local_repo_explorer_preferences": ["grouping_mode", "sort_order", "visibility_mode", "updated_at"],
    "local_inbox_notification_preferences": [
        "grouping", "sort_order", "bell_enabled", "global_content_mode", "global_row_state_filter",
        "pane_content_mode", "pane_row_state_filter", "updated_at",
    ],
    "cache_metadata": ["source_revision"],
    "cache_repo_enrichment": ["state", "updated_at"],
    "cache_worktree_enrichment": ["repo_id", "is_main_worktree", "updated_at"],
    "cache_pull_request_count": ["count", "updated_at"],
]

private func assertLocalSchemaStructuralContract(in databaseQueue: DatabaseQueue) throws {
    try assertColumnContracts(in: databaseQueue)
    try assertForeignKeyContracts(in: databaseQueue)
    try assertCheckContracts(in: databaseQueue)
}

private func assertColumnContracts(in databaseQueue: DatabaseQueue) throws {
    let expectedColumns = localSchemaExpectedColumns
    let expectedTypes = localSchemaExpectedTypes
    let expectedNotNullColumns = localSchemaExpectedNotNullColumns

    for (tableName, expected) in expectedColumns {
        let actualRows = try databaseQueue.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(\(tableName))")
        }
        #expect(actualRows.map { $0["name"] as String } == expected.map(\.0))
        #expect(actualRows.map { $0["type"] as String } == expectedTypes[tableName])
        #expect(actualRows.map { $0["pk"] as Int } == expected.map(\.1))
        #expect(
            Set(actualRows.compactMap { row in (row["notnull"] as Int) == 1 ? row["name"] as String : nil })
                == expectedNotNullColumns[tableName]
        )
        let declaredDefaults = Dictionary(
            uniqueKeysWithValues: actualRows.compactMap { row -> (String, String)? in
                guard let defaultValue: String = row["dflt_value"] else { return nil }
                return (row["name"] as String, defaultValue)
            }
        )
        let expectedDefaults = tableName == "cache_metadata" ? ["source_revision": "0"] : [:]
        #expect(declaredDefaults == expectedDefaults)
    }
}

private func assertForeignKeyContracts(in databaseQueue: DatabaseQueue) throws {
    var allForeignKeys: [LocalSchemaForeignKeyContract] = []
    for tableName in localSchemaExpectedColumns.keys.sorted() {
        let tableForeignKeys: [LocalSchemaForeignKeyContract] = try databaseQueue.read { database in
            try Row.fetchAll(database, sql: "PRAGMA foreign_key_list(\(tableName))").map { row in
                LocalSchemaForeignKeyContract(
                    sourceTable: tableName,
                    targetTable: row["table"],
                    sourceColumn: row["from"],
                    targetColumn: row["to"],
                    onDelete: row["on_delete"]
                )
            }
        }
        allForeignKeys.append(contentsOf: tableForeignKeys)
    }
    #expect(
        allForeignKeys == [
            LocalSchemaForeignKeyContract(
                sourceTable: "local_window_sidebar_expanded_group",
                targetTable: "local_window_state",
                sourceColumn: "window_id",
                targetColumn: "window_id",
                onDelete: "CASCADE"
            )
        ]
    )
}

private func assertCheckContracts(in databaseQueue: DatabaseQueue) throws {
    let tableSQL: [String: String] = try databaseQueue.read { database in
        try Dictionary(
            uniqueKeysWithValues: Row.fetchAll(
                database,
                sql: """
                    SELECT name, sql
                    FROM sqlite_master
                    WHERE type = 'table'
                      AND name NOT LIKE 'sqlite_%'
                      AND name != 'grdb_migrations'
                    """
            ).map { row in (row["name"] as String, row["sql"] as String) }
        )
    }
    #expect(Set(tableSQL.keys) == Set(localSchemaExpectedColumns.keys))
    let expectedCheckCounts: [String: Int] = [
        "local_workspace_cursor": 0,
        "local_tab_cursor": 0,
        "local_arrangement_cursor": 0,
        "local_drawer_cursor": 1,
        "local_arrangement_drawer_cursor": 0,
        "local_window_state": 3,
        "local_window_sidebar_expanded_group": 0,
        "local_recent_workspace_target": 0,
        "local_notification_inbox_collapsed_group": 0,
        "local_notification_inbox_item": 2,
        "local_editor_preferences": 0,
        "local_repo_explorer_preferences": 0,
        "local_inbox_notification_preferences": 1,
        "cache_metadata": 2,
        "cache_repo_enrichment": 0,
        "cache_worktree_enrichment": 1,
        "cache_pull_request_count": 1,
    ]
    for (tableName, expectedCheckCount) in expectedCheckCounts {
        let tableDefinition = try #require(tableSQL[tableName])
        #expect(tableDefinition.components(separatedBy: "CHECK (").count - 1 == expectedCheckCount)
    }
    #expect(tableSQL["local_window_state"]?.components(separatedBy: "CHECK (").count == 4)
    #expect(tableSQL["local_window_state"]?.contains("window_role = 'main'") == true)
    #expect(tableSQL["local_window_state"]?.contains("is_filter_visible IN (0, 1)") == true)
    #expect(tableSQL["local_window_state"]?.contains("sidebar_collapsed IN (0, 1)") == true)
    #expect(tableSQL["local_window_sidebar_expanded_group"]?.contains("ON DELETE CASCADE") == true)
    #expect(tableSQL["local_recent_workspace_target"]?.contains("CHECK (") == false)
    #expect(tableSQL["local_notification_inbox_item"]?.components(separatedBy: "CHECK (").count == 3)
    #expect(tableSQL["local_notification_inbox_item"]?.contains("is_read IN (0, 1)") == true)
    #expect(
        tableSQL["local_notification_inbox_item"]?.contains("is_dismissed_from_pane_inbox IN (0, 1)")
            == true
    )
    #expect(tableSQL["local_notification_inbox_item"]?.contains("kind IN") == false)
    #expect(tableSQL["local_notification_inbox_item"]?.contains("claim_lane IN") == false)
    #expect(tableSQL["local_drawer_cursor"]?.contains("is_expanded IN (0, 1)") == true)
    #expect(tableSQL["local_inbox_notification_preferences"]?.contains("bell_enabled IN (0, 1)") == true)
    #expect(tableSQL["cache_metadata"]?.contains("singleton_id = 1") == true)
    #expect(tableSQL["cache_metadata"]?.contains("source_revision >= 0") == true)
    #expect(tableSQL["cache_worktree_enrichment"]?.contains("is_main_worktree IN (0, 1)") == true)
    #expect(tableSQL["cache_pull_request_count"]?.contains("count >= 0") == true)
}

extension WorkspaceLocalSchemaContractTests {
    @Test("drawer expansion switch must collapse before expanding replacement")
    func drawerExpansionSwitchMustCollapseBeforeExpandingReplacement() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let workspaceId = UUID().uuidString
        let firstDrawerId = UUID().uuidString
        let secondDrawerId = UUID().uuidString

        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO local_drawer_cursor(drawer_id, workspace_id, is_expanded, updated_at)
                    VALUES (?, ?, ?, ?), (?, ?, ?, ?)
                    """,
                arguments: [
                    firstDrawerId, workspaceId, 1, 1.0,
                    secondDrawerId, workspaceId, 0, 1.0,
                ]
            )
        }

        expectSchemaContractDatabaseError(containing: "UNIQUE constraint failed") {
            try databaseQueue.write { database in
                try database.execute(
                    sql: """
                        UPDATE local_drawer_cursor
                        SET is_expanded = 1
                        WHERE drawer_id = ?
                        """,
                    arguments: [secondDrawerId]
                )
            }
        }

        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    UPDATE local_drawer_cursor
                    SET is_expanded = 0
                    WHERE drawer_id = ?
                    """,
                arguments: [firstDrawerId]
            )
            try database.execute(
                sql: """
                    UPDATE local_drawer_cursor
                    SET is_expanded = 1
                    WHERE drawer_id = ?
                    """,
                arguments: [secondDrawerId]
            )
        }
    }
}

private func expectSchemaContractDatabaseError(containing expectedMessage: String, _ operation: () throws -> Void) {
    do {
        try operation()
        Issue.record("Expected DatabaseError containing '\(expectedMessage)'")
    } catch let error as DatabaseError {
        #expect(error.message?.contains(expectedMessage) == true)
    } catch {
        Issue.record("Expected DatabaseError, got \(error)")
    }
}
