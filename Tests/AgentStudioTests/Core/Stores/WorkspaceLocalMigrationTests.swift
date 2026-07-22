import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("WorkspaceLocalMigrationTests")
struct WorkspaceLocalMigrationTests {
    @Test("fresh local database creates exactly the clean product schema")
    func freshLocalDatabaseCreatesExactlyTheCleanProductSchema() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()

        try WorkspaceLocalMigrations.migrate(databaseQueue)

        let tableNames = try databaseQueue.read { database in
            try Set(
                String.fetchAll(
                    database,
                    sql: """
                        SELECT name
                        FROM sqlite_master
                        WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'
                        """
                )
            )
        }
        let expectedTableNames: Set<String> = [
            "local_workspace_cursor",
            "local_tab_cursor",
            "local_arrangement_cursor",
            "local_drawer_cursor",
            "local_arrangement_drawer_cursor",
            "local_window_state",
            "local_window_sidebar_expanded_group",
            "local_recent_workspace_target",
            "local_notification_inbox_collapsed_group",
            "local_notification_inbox_item",
            "local_editor_preferences",
            "local_repo_explorer_preferences",
            "local_inbox_notification_preferences",
            "cache_metadata",
            "cache_repo_enrichment",
            "cache_worktree_enrichment",
            "cache_pull_request_count",
        ]

        #expect(tableNames == expectedTableNames)
        #expect(!tableNames.contains("local_persistence_lane_marker"))
        #expect(!tableNames.contains("local_workspace_sqlite_snapshot_status"))
        #expect(!tableNames.contains("cache_notification_count"))
    }

    @Test("clean local schema has one initial migration")
    func cleanLocalSchemaHasOneInitialMigration() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()

        try WorkspaceLocalMigrations.migrate(databaseQueue)
        try WorkspaceLocalMigrations.migrate(databaseQueue)

        let completedMigrations = try databaseQueue.read { database in
            try WorkspaceLocalMigrations.migrator.completedMigrations(database)
        }

        #expect(completedMigrations == ["001_create_application_local_schema"])
    }

    @Test("workspace cursor keys isolate rows in one database")
    func workspaceCursorKeysIsolateRowsInOneDatabase() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let firstWorkspaceId = UUID().uuidString
        let secondWorkspaceId = UUID().uuidString
        let sharedTabId = UUID().uuidString

        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO local_tab_cursor(workspace_id, tab_id, active_arrangement_id, updated_at)
                    VALUES (?, ?, NULL, 1), (?, ?, NULL, 2)
                    """,
                arguments: [firstWorkspaceId, sharedTabId, secondWorkspaceId, sharedTabId]
            )
        }

        let workspaceIds = try databaseQueue.read { database in
            try String.fetchAll(database, sql: "SELECT workspace_id FROM local_tab_cursor ORDER BY updated_at")
        }
        #expect(workspaceIds == [firstWorkspaceId, secondWorkspaceId])
    }

    @Test("window role is one stable main row and child rows cascade")
    func windowRoleIsOneStableMainRowAndChildRowsCascade() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let windowId = UUID().uuidString

        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO local_window_state(
                        window_id, window_role, sidebar_width, window_frame_json, filter_text,
                        is_filter_visible, sidebar_collapsed, sidebar_surface, updated_at
                    ) VALUES (?, 'main', 240, NULL, '', 0, 0, 'repos', 1)
                    """,
                arguments: [windowId]
            )
            try database.execute(
                sql: "INSERT INTO local_window_sidebar_expanded_group(window_id, group_key) VALUES (?, 'repo:test')",
                arguments: [windowId]
            )
        }

        expectLocalDatabaseError(containing: "UNIQUE constraint failed") {
            try databaseQueue.write { database in
                try database.execute(
                    sql: """
                        INSERT INTO local_window_state(
                            window_id, window_role, sidebar_width, window_frame_json, filter_text,
                            is_filter_visible, sidebar_collapsed, sidebar_surface, updated_at
                        ) VALUES (?, 'main', 250, NULL, '', 0, 0, 'inbox', 2)
                        """,
                    arguments: [UUID().uuidString]
                )
            }
        }

        try databaseQueue.write { database in
            try database.execute(sql: "DELETE FROM local_window_state WHERE window_id = ?", arguments: [windowId])
        }
        let childCount = try databaseQueue.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM local_window_sidebar_expanded_group") ?? -1
        }
        #expect(childCount == 0)
    }

    @Test("SQLite enforces structural values without product enum checks")
    func sqliteEnforcesStructuralValuesWithoutProductEnumChecks() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let workspaceId = UUID().uuidString

        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO local_recent_workspace_target(
                        workspace_id, id, path, display_title, subtitle, repo_id, worktree_id, kind, last_opened_at
                    ) VALUES (?, 'target', '/tmp', 'Title', '', NULL, NULL, 'futureKind', 1)
                    """,
                arguments: [workspaceId]
            )
            try database.execute(
                sql: """
                    INSERT INTO local_notification_inbox_item(
                        workspace_id, id, timestamp, kind, title, source_kind,
                        claim_pane_id, claim_lane, claim_semantic, claim_session_id,
                        is_read, is_dismissed_from_pane_inbox
                    ) VALUES (?, 'notification', 1, 'futureKind', 'Title', 'global', NULL, 'futureLane', NULL, NULL, 0, 0)
                    """,
                arguments: [workspaceId]
            )
        }

        expectLocalDatabaseError(containing: "CHECK constraint failed") {
            try databaseQueue.write { database in
                try database.execute(
                    sql: """
                        INSERT INTO local_drawer_cursor(workspace_id, drawer_id, is_expanded, updated_at)
                        VALUES (?, ?, 2, 1)
                        """,
                    arguments: [workspaceId, UUID().uuidString]
                )
            }
        }
        expectLocalDatabaseError(containing: "CHECK constraint failed") {
            try databaseQueue.write { database in
                try database.execute(
                    sql: "INSERT INTO cache_metadata(singleton_id, source_revision) VALUES (2, 0)"
                )
            }
        }
    }
}

private func expectLocalDatabaseError(containing expectedMessage: String, _ operation: () throws -> Void) {
    do {
        try operation()
        Issue.record("Expected DatabaseError containing '\(expectedMessage)'")
    } catch let error as DatabaseError {
        #expect(error.message?.contains(expectedMessage) == true)
    } catch {
        Issue.record("Expected DatabaseError, got \(error)")
    }
}
