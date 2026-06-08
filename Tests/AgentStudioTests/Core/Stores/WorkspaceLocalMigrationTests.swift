import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("WorkspaceLocalMigrationTests")
struct WorkspaceLocalMigrationTests {
    @Test("fresh local database creates local and cache tables")
    func freshLocalDatabaseCreatesLocalAndCacheTables() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()

        try WorkspaceLocalMigrations.migrate(databaseQueue)

        let tableNames = try databaseQueue.read { database in
            try String.fetchAll(
                database,
                sql: """
                    SELECT name
                    FROM sqlite_master
                    WHERE type = 'table'
                    ORDER BY name
                    """
            )
        }

        #expect(tableNames.contains("local_workspace_cursor"))
        #expect(tableNames.contains("local_tab_cursor"))
        #expect(tableNames.contains("local_arrangement_cursor"))
        #expect(tableNames.contains("local_drawer_cursor"))
        #expect(tableNames.contains("local_arrangement_drawer_cursor"))
        #expect(tableNames.contains("local_workspace_window_state"))
        #expect(tableNames.contains("local_sidebar_state"))
        #expect(tableNames.contains("local_sidebar_expanded_group"))
        #expect(tableNames.contains("local_recent_workspace_target"))
        #expect(tableNames.contains("local_persistence_lane_marker"))
        #expect(tableNames.contains("local_workspace_sqlite_snapshot_status"))
        #expect(tableNames.contains("local_notification_inbox_collapsed_group"))
        #expect(tableNames.contains("local_notification_inbox_item"))
        #expect(tableNames.contains("cache_metadata"))
        #expect(tableNames.contains("cache_repo_enrichment"))
        #expect(tableNames.contains("cache_worktree_enrichment"))
        #expect(tableNames.contains("cache_pull_request_count"))
        #expect(tableNames.contains("cache_notification_count"))
    }

    @Test("migration identifiers are stable and run once")
    func migrationIdentifiersAreStableAndRunOnce() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()

        try WorkspaceLocalMigrations.migrate(databaseQueue)
        try WorkspaceLocalMigrations.migrate(databaseQueue)

        let completedMigrations = try databaseQueue.read { database in
            try WorkspaceLocalMigrations.migrator.completedMigrations(database)
        }

        #expect(
            completedMigrations == [
                "001_create_local_cursors",
                "002_create_local_workspace_memory",
                "003_create_local_notifications",
                "004_create_cache_tables",
                "005_enforce_notification_claim_keys",
                "006_create_local_persistence_lane_markers",
                "007_create_local_workspace_sqlite_snapshot_status",
            ]
        )
    }

    @Test("snapshot status migration backfills existing workspace cursor timestamp")
    func snapshotStatusMigrationBackfillsExistingWorkspaceCursorTimestamp() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        let workspaceId = UUID().uuidString
        let completedAt = 700.0
        try WorkspaceLocalMigrations.migrator.migrate(
            databaseQueue,
            upTo: "006_create_local_persistence_lane_markers"
        )
        let tableExistsBeforeSnapshotStatusMigration = try databaseQueue.read { database in
            try Bool.fetchOne(
                database,
                sql: """
                    SELECT EXISTS (
                        SELECT 1
                        FROM sqlite_master
                        WHERE type = 'table'
                          AND name = 'local_workspace_sqlite_snapshot_status'
                    )
                    """
            ) ?? false
        }
        #expect(!tableExistsBeforeSnapshotStatusMigration)
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO local_workspace_cursor(workspace_id, active_tab_id, updated_at)
                    VALUES (?, NULL, ?)
                    """,
                arguments: [workspaceId, completedAt]
            )
        }

        try WorkspaceLocalMigrations.migrate(databaseQueue)

        let restoredCompletedAt = try databaseQueue.read { database in
            try Double.fetchOne(
                database,
                sql: """
                    SELECT completed_at
                    FROM local_workspace_sqlite_snapshot_status
                    WHERE workspace_id = ?
                    """,
                arguments: [workspaceId]
            )
        }
        #expect(restoredCompletedAt == completedAt)
    }

    @Test("active drawer child cursor is scoped by arrangement and drawer")
    func activeDrawerChildCursorIsScopedByArrangementAndDrawer() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let workspaceId = UUID().uuidString
        let drawerId = UUID().uuidString
        let firstArrangementId = UUID().uuidString
        let secondArrangementId = UUID().uuidString

        try databaseQueue.write { database in
            try insertArrangementDrawerCursor(
                database,
                workspaceId: workspaceId,
                arrangementId: firstArrangementId,
                drawerId: drawerId,
                activeChildId: UUID().uuidString
            )
            try insertArrangementDrawerCursor(
                database,
                workspaceId: workspaceId,
                arrangementId: secondArrangementId,
                drawerId: drawerId,
                activeChildId: UUID().uuidString
            )
        }

        expectDatabaseError(containing: "UNIQUE constraint failed") {
            try databaseQueue.write { database in
                try insertArrangementDrawerCursor(
                    database,
                    workspaceId: workspaceId,
                    arrangementId: firstArrangementId,
                    drawerId: drawerId,
                    activeChildId: UUID().uuidString
                )
            }
        }
    }

    @Test("local boolean columns reject non boolean values")
    func localBooleanColumnsRejectNonBooleanValues() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let workspaceId = UUID().uuidString

        expectDatabaseError(containing: "CHECK constraint failed") {
            try databaseQueue.write { database in
                try database.execute(
                    sql: """
                        INSERT INTO local_drawer_cursor(drawer_id, workspace_id, is_expanded, updated_at)
                        VALUES (?, ?, ?, ?)
                        """,
                    arguments: [UUID().uuidString, workspaceId, 2, 1.0]
                )
            }
        }

        expectDatabaseError(containing: "CHECK constraint failed") {
            try databaseQueue.write { database in
                try database.execute(
                    sql: """
                        INSERT INTO local_notification_inbox_item(
                            id, workspace_id, timestamp, kind, title, source_kind,
                            is_read, is_dismissed_from_pane_inbox
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        UUID().uuidString,
                        workspaceId,
                        1.0,
                        "activity",
                        "Terminal activity",
                        "terminal",
                        3,
                        0,
                    ]
                )
            }
        }

    }

    @Test("drawer expansion storage allows one expanded drawer per workspace")
    func drawerExpansionStorageAllowsOneExpandedDrawerPerWorkspace() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let firstWorkspaceId = UUID().uuidString
        let secondWorkspaceId = UUID().uuidString

        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO local_drawer_cursor(drawer_id, workspace_id, is_expanded, updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [UUID().uuidString, firstWorkspaceId, 1, 1.0]
            )
            try database.execute(
                sql: """
                    INSERT INTO local_drawer_cursor(drawer_id, workspace_id, is_expanded, updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [UUID().uuidString, firstWorkspaceId, 0, 1.0]
            )
            try database.execute(
                sql: """
                    INSERT INTO local_drawer_cursor(drawer_id, workspace_id, is_expanded, updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [UUID().uuidString, secondWorkspaceId, 1, 1.0]
            )
        }

        expectDatabaseError(containing: "UNIQUE constraint failed") {
            try databaseQueue.write { database in
                try database.execute(
                    sql: """
                        INSERT INTO local_drawer_cursor(drawer_id, workspace_id, is_expanded, updated_at)
                        VALUES (?, ?, ?, ?)
                        """,
                    arguments: [UUID().uuidString, firstWorkspaceId, 1, 1.0]
                )
            }
        }
    }

    @Test("sidebar surface rejects unsupported values")
    func sidebarSurfaceRejectsUnsupportedValues() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)

        expectDatabaseError(containing: "CHECK constraint failed") {
            try databaseQueue.write { database in
                try database.execute(
                    sql: """
                        INSERT INTO local_sidebar_state(
                            workspace_id, filter_text, is_filter_visible,
                            sidebar_collapsed, sidebar_surface, updated_at
                        )
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        UUID().uuidString,
                        "",
                        0,
                        0,
                        "settings",
                        1.0,
                    ]
                )
            }
        }
    }

    @Test("recent workspace target rejects mismatched referent shape")
    func recentWorkspaceTargetRejectsMismatchedReferentShape() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let workspaceId = UUID().uuidString

        expectDatabaseError(containing: "CHECK constraint failed") {
            try databaseQueue.write { database in
                try insertRecentWorkspaceTarget(
                    database,
                    workspaceId: workspaceId,
                    kind: "worktree",
                    repoId: nil,
                    worktreeId: nil
                )
            }
        }

        expectDatabaseError(containing: "CHECK constraint failed") {
            try databaseQueue.write { database in
                try insertRecentWorkspaceTarget(
                    database,
                    workspaceId: workspaceId,
                    kind: "cwdOnly",
                    repoId: UUID().uuidString,
                    worktreeId: UUID().uuidString
                )
            }
        }

        expectDatabaseError(containing: "CHECK constraint failed") {
            try databaseQueue.write { database in
                try insertRecentWorkspaceTarget(
                    database,
                    workspaceId: workspaceId,
                    kind: "unknown",
                    repoId: nil,
                    worktreeId: nil
                )
            }
        }
    }

    @Test("notification claim storage allows non coalescing safety duplicates")
    func notificationClaimStorageAllowsNonCoalescingSafetyDuplicates() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let workspaceId = UUID().uuidString
        let claimPaneId = UUID().uuidString

        try databaseQueue.write { database in
            try insertNotification(
                database,
                record: .init(
                    workspaceId: workspaceId,
                    id: UUID().uuidString,
                    claimPaneId: claimPaneId,
                    claimLane: "safety",
                    claimSemantic: "securityEvent",
                    claimSessionId: nil
                )
            )
            try insertNotification(
                database,
                record: .init(
                    workspaceId: workspaceId,
                    id: UUID().uuidString,
                    claimPaneId: claimPaneId,
                    claimLane: "safety",
                    claimSemantic: "securityEvent",
                    claimSessionId: nil
                )
            )

            let notificationCount = try Int.fetchOne(
                database,
                sql: """
                    SELECT COUNT(*)
                    FROM local_notification_inbox_item
                    WHERE workspace_id = ?
                    """,
                arguments: [workspaceId]
            )
            #expect(notificationCount == 2)
        }
    }

    @Test("notification claim storage allows distinct active and dismissed claim candidates")
    func notificationClaimStorageAllowsDistinctActiveAndDismissedClaimCandidates() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let workspaceId = UUID().uuidString
        let claimPaneId = UUID().uuidString

        try databaseQueue.write { database in
            try insertNotification(
                database,
                record: .init(
                    workspaceId: workspaceId,
                    id: UUID().uuidString,
                    claimPaneId: claimPaneId,
                    claimLane: "activity",
                    claimSemantic: "unseenActivity",
                    claimSessionId: nil,
                    isRead: true,
                    isDismissedFromPaneInbox: true
                )
            )
            try insertNotification(
                database,
                record: .init(
                    workspaceId: workspaceId,
                    id: UUID().uuidString,
                    claimPaneId: claimPaneId,
                    claimLane: "activity",
                    claimSemantic: "unseenActivity",
                    claimSessionId: nil,
                    isRead: false,
                    isDismissedFromPaneInbox: false
                )
            )

            let notificationCount = try Int.fetchOne(
                database,
                sql: """
                    SELECT COUNT(*)
                    FROM local_notification_inbox_item
                    WHERE workspace_id = ?
                    """,
                arguments: [workspaceId]
            )
            #expect(notificationCount == 2)
        }
    }

    @Test("notification claim storage allows valid claim keys for every lane with optional session ids")
    func notificationClaimStorageAllowsValidClaimKeysForEveryLaneWithOptionalSessionIds() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let workspaceId = UUID().uuidString
        let claimPaneId = UUID().uuidString

        try databaseQueue.write { database in
            for claimLane in [
                SQLiteInboxNotificationClaimStorage.laneActivity,
                SQLiteInboxNotificationClaimStorage.laneActionNeeded,
                SQLiteInboxNotificationClaimStorage.laneSafety,
            ] {
                try insertNotification(
                    database,
                    record: .init(
                        workspaceId: workspaceId,
                        id: UUID().uuidString,
                        claimPaneId: claimPaneId,
                        claimLane: claimLane,
                        claimSemantic: "unseenActivity",
                        claimSessionId: nil
                    )
                )
            }

            let notificationCount = try Int.fetchOne(
                database,
                sql: """
                    SELECT COUNT(*)
                    FROM local_notification_inbox_item
                    WHERE workspace_id = ?
                    """,
                arguments: [workspaceId]
            )
            #expect(notificationCount == 3)
        }
    }

    @Test("notification claim storage rejects invalid claim lane")
    func notificationClaimStorageRejectsInvalidClaimLane() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)

        expectDatabaseError(containing: "CHECK constraint failed") {
            try databaseQueue.write { database in
                try insertNotification(
                    database,
                    record: .init(
                        workspaceId: UUID().uuidString,
                        id: UUID().uuidString,
                        claimPaneId: UUID().uuidString,
                        claimLane: "unknown",
                        claimSemantic: "unseenActivity",
                        claimSessionId: nil
                    )
                )
            }
        }

        expectDatabaseError(containing: "CHECK constraint failed") {
            try databaseQueue.write { database in
                try insertNotification(
                    database,
                    record: .init(
                        workspaceId: UUID().uuidString,
                        id: UUID().uuidString,
                        claimPaneId: nil,
                        claimLane: nil,
                        claimSemantic: nil,
                        claimSessionId: UUID().uuidString
                    )
                )
            }
        }
    }

    @Test("notification claim storage rejects partial claim keys")
    func notificationClaimStorageRejectsPartialClaimKeys() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let workspaceId = UUID().uuidString

        expectDatabaseError(containing: "CHECK constraint failed") {
            try databaseQueue.write { database in
                try insertNotification(
                    database,
                    record: .init(
                        workspaceId: workspaceId,
                        id: UUID().uuidString,
                        claimPaneId: UUID().uuidString,
                        claimLane: nil,
                        claimSemantic: "unseenActivity",
                        claimSessionId: nil
                    )
                )
            }
        }

        expectDatabaseError(containing: "CHECK constraint failed") {
            try databaseQueue.write { database in
                try insertNotification(
                    database,
                    record: .init(
                        workspaceId: workspaceId,
                        id: UUID().uuidString,
                        claimPaneId: nil,
                        claimLane: "activity",
                        claimSemantic: "unseenActivity",
                        claimSessionId: nil
                    )
                )
            }
        }
    }

    @Test("local workspace cursor and window memory round trip")
    func localWorkspaceCursorAndWindowMemoryRoundTrip() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let workspaceId = UUID().uuidString
        let activeTabId = UUID().uuidString
        let windowFrameJSON = #"{"x":10,"y":20,"width":1200,"height":800}"#

        let restored = try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO local_workspace_cursor(workspace_id, active_tab_id, updated_at)
                    VALUES (?, ?, ?)
                    """,
                arguments: [workspaceId, activeTabId, 1.0]
            )
            try database.execute(
                sql: """
                    INSERT INTO local_workspace_window_state(
                        workspace_id, sidebar_width, window_frame_json, updated_at
                    )
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [workspaceId, 280.0, windowFrameJSON, 2.0]
            )
            return try Row.fetchOne(
                database,
                sql: """
                    SELECT cursor.active_tab_id, window.sidebar_width, window.window_frame_json
                    FROM local_workspace_cursor cursor
                    JOIN local_workspace_window_state window
                        ON window.workspace_id = cursor.workspace_id
                    WHERE cursor.workspace_id = ?
                    """,
                arguments: [workspaceId]
            )
        }

        #expect(restored?["active_tab_id"] as String? == activeTabId)
        #expect(restored?["sidebar_width"] as Double? == 280.0)
        #expect(restored?["window_frame_json"] as String? == windowFrameJSON)
    }

    @Test("recent workspace target and notification inbox item round trip")
    func recentWorkspaceTargetAndNotificationInboxItemRoundTrip() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let workspaceId = UUID().uuidString
        let targetId = UUID().uuidString
        let notificationId = UUID().uuidString

        let restored = try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO local_recent_workspace_target(
                        id, workspace_id, path, display_title, subtitle, repo_id, worktree_id, kind, last_opened_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    targetId,
                    workspaceId,
                    "/tmp/project",
                    "project",
                    "main",
                    "repo-1",
                    "worktree-1",
                    "worktree",
                    3.0,
                ]
            )
            try database.execute(
                sql: """
                    INSERT INTO local_notification_inbox_item(
                        id, workspace_id, timestamp, kind, title, body, source_kind,
                        pane_id, tab_id, repo_id, worktree_id, branch_name,
                        is_read, is_dismissed_from_pane_inbox
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    notificationId,
                    workspaceId,
                    4.0,
                    "activity",
                    "Terminal activity",
                    "12 new rows",
                    "terminal",
                    "pane-1",
                    "tab-1",
                    "repo-1",
                    "worktree-1",
                    "main",
                    0,
                    1,
                ]
            )
            return try Row.fetchOne(
                database,
                sql: """
                    SELECT target.display_title, notification.title, notification.is_dismissed_from_pane_inbox
                    FROM local_recent_workspace_target target
                    JOIN local_notification_inbox_item notification
                        ON notification.workspace_id = target.workspace_id
                    WHERE target.id = ? AND notification.id = ?
                    """,
                arguments: [targetId, notificationId]
            )
        }

        #expect(restored?["display_title"] as String? == "project")
        #expect(restored?["title"] as String? == "Terminal activity")
        #expect(restored?["is_dismissed_from_pane_inbox"] as Int? == 1)
    }

}

private func insertRecentWorkspaceTarget(
    _ database: Database,
    workspaceId: String,
    kind: String,
    repoId: String?,
    worktreeId: String?
) throws {
    try database.execute(
        sql: """
            INSERT INTO local_recent_workspace_target(
                id, workspace_id, path, display_title, subtitle, repo_id, worktree_id, kind, last_opened_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
        arguments: [
            UUID().uuidString,
            workspaceId,
            "/tmp/project",
            "project",
            "subtitle",
            repoId,
            worktreeId,
            kind,
            1.0,
        ]
    )
}

private struct NotificationRecord {
    let workspaceId: String
    let id: String
    let claimPaneId: String?
    let claimLane: String?
    let claimSemantic: String?
    let claimSessionId: String?
    var isRead = false
    var isDismissedFromPaneInbox = false
}

private func insertNotification(_ database: Database, record: NotificationRecord) throws {
    try database.execute(
        sql: """
            INSERT INTO local_notification_inbox_item(
                id, workspace_id, timestamp, kind, title, source_kind,
                claim_pane_id, claim_lane, claim_semantic, claim_session_id,
                is_read, is_dismissed_from_pane_inbox
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
        arguments: [
            record.id,
            record.workspaceId,
            1.0,
            "activity",
            "Terminal activity",
            "terminal",
            record.claimPaneId,
            record.claimLane,
            record.claimSemantic,
            record.claimSessionId,
            record.isRead ? 1 : 0,
            record.isDismissedFromPaneInbox ? 1 : 0,
        ]
    )
}

private func insertArrangementDrawerCursor(
    _ database: Database,
    workspaceId: String,
    arrangementId: String,
    drawerId: String,
    activeChildId: String?
) throws {
    try database.execute(
        sql: """
            INSERT INTO local_arrangement_drawer_cursor(
                arrangement_id, drawer_id, workspace_id, active_child_id, updated_at
            )
            VALUES (?, ?, ?, ?, ?)
            """,
        arguments: [arrangementId, drawerId, workspaceId, activeChildId, 1.0]
    )
}

private func expectDatabaseError(containing expectedMessage: String, _ operation: () throws -> Void) {
    do {
        try operation()
        Issue.record("Expected DatabaseError containing '\(expectedMessage)'")
    } catch let error as DatabaseError {
        #expect(error.message?.contains(expectedMessage) == true)
    } catch {
        Issue.record("Expected DatabaseError, got \(error)")
    }
}
