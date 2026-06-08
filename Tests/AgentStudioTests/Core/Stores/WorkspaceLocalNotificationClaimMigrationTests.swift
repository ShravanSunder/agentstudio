import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("WorkspaceLocalNotificationClaimMigrationTests")
struct WorkspaceLocalNotificationClaimMigrationTests {
    @Test("notification claim enforcement migration preserves rows and normalizes malformed claims")
    func notificationClaimEnforcementMigrationPreservesRowsAndNormalizesMalformedClaims() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        let fixture = LegacyNotificationClaimMigrationFixture()

        try databaseQueue.write { database in
            try createLegacyNotificationInboxItemBeforeClaimKeyEnforcement(database)
            try markCompletedLocalMigrationsBeforeClaimKeyEnforcement(database)
            try seedLegacyNotificationsBeforeClaimKeyEnforcement(database, fixture: fixture)
        }

        try WorkspaceLocalMigrations.migrate(databaseQueue)

        let migratedRowsById = try fetchMigratedNotificationRowsById(databaseQueue)
        let completedMigrations = try databaseQueue.read { database in
            try WorkspaceLocalMigrations.migrator.completedMigrations(database)
        }

        #expect(migratedRowsById.count == 6)
        expectActivityNotificationPreserved(
            migratedRowsById[fixture.validActivityId], sessionId: fixture.activitySessionId)
        expectActionNeededNotificationPreserved(
            migratedRowsById[fixture.validActionNeededId],
            claimPaneId: fixture.actionNeededClaimPaneId,
            claimSessionId: fixture.actionNeededSessionId
        )
        expectSafetyNotificationPreserved(
            migratedRowsById[fixture.validSafetyId],
            claimPaneId: fixture.safetyClaimPaneId
        )
        expectMalformedClaimsNormalized(migratedRowsById, fixture: fixture)
        #expect(completedMigrations.contains("005_enforce_notification_claim_keys"))
        #expect(completedMigrations.last == "007_create_local_workspace_sqlite_snapshot_status")
    }
}

private struct LegacyNotificationClaimMigrationFixture {
    let workspaceId = UUID().uuidString
    let validActivityId = UUID().uuidString
    let validActionNeededId = UUID().uuidString
    let validSafetyId = UUID().uuidString
    let unknownLaneId = UUID().uuidString
    let partialClaimId = UUID().uuidString
    let sessionOnlyId = UUID().uuidString
    let activitySessionId = UUID().uuidString
    let actionNeededSessionId = UUID().uuidString
    let actionNeededClaimPaneId = UUID().uuidString
    let safetyClaimPaneId = UUID().uuidString
}

private func seedLegacyNotificationsBeforeClaimKeyEnforcement(
    _ database: Database,
    fixture: LegacyNotificationClaimMigrationFixture
) throws {
    try insertLegacyNotification(
        database,
        record: .init(
            workspaceId: fixture.workspaceId,
            id: fixture.validActivityId,
            claimPaneId: UUID().uuidString,
            claimLane: "activity",
            claimSemantic: "unseenActivity",
            claimSessionId: fixture.activitySessionId
        )
    )
    try insertLegacyNotification(
        database,
        record: makeActionNeededLegacyNotificationRecord(
            workspaceId: fixture.workspaceId,
            id: fixture.validActionNeededId,
            claimPaneId: fixture.actionNeededClaimPaneId,
            claimSessionId: fixture.actionNeededSessionId
        )
    )
    try insertLegacyNotification(
        database,
        record: .init(
            workspaceId: fixture.workspaceId,
            id: fixture.validSafetyId,
            claimPaneId: fixture.safetyClaimPaneId,
            claimLane: "safety",
            claimSemantic: "securityEvent",
            claimSessionId: nil
        )
    )
    try insertLegacyNotification(
        database,
        record: .init(
            workspaceId: fixture.workspaceId,
            id: fixture.unknownLaneId,
            claimPaneId: UUID().uuidString,
            claimLane: "unknown",
            claimSemantic: "unseenActivity",
            claimSessionId: nil
        )
    )
    try insertLegacyNotification(
        database,
        record: .init(
            workspaceId: fixture.workspaceId,
            id: fixture.partialClaimId,
            claimPaneId: UUID().uuidString,
            claimLane: nil,
            claimSemantic: "unseenActivity",
            claimSessionId: nil
        )
    )
    try insertLegacyNotification(
        database,
        record: .init(
            workspaceId: fixture.workspaceId,
            id: fixture.sessionOnlyId,
            claimPaneId: nil,
            claimLane: nil,
            claimSemantic: nil,
            claimSessionId: UUID().uuidString
        )
    )
}

private func fetchMigratedNotificationRowsById(_ databaseQueue: DatabaseQueue) throws -> [String: Row] {
    let migratedRows = try databaseQueue.read { database in
        try Row.fetchAll(
            database,
            sql: """
                SELECT *
                FROM local_notification_inbox_item
                ORDER BY id
                """
        )
    }
    return Dictionary(
        uniqueKeysWithValues: migratedRows.compactMap { row in
            (row["id"] as String?).map { ($0, row) }
        })
}

private func makeActionNeededLegacyNotificationRecord(
    workspaceId: String,
    id: String,
    claimPaneId: String,
    claimSessionId: String
) -> LegacyNotificationRecord {
    .init(
        workspaceId: workspaceId,
        id: id,
        timestamp: 11.5,
        kind: "action",
        title: "Action needed",
        body: "Review required",
        sourceKind: "agent",
        paneId: "pane-action",
        tabId: "tab-action",
        tabDisplayLabel: "Tab A",
        tabOrdinal: 2,
        repoId: "repo-action",
        repoName: "agentstudio",
        worktreeId: "worktree-action",
        worktreeName: "feature/sqlite",
        branchName: "sqlite",
        paneDisplayLabel: "Pane A",
        paneOrdinal: 3,
        paneRole: "terminal",
        parentPaneId: "parent-pane-action",
        parentPaneDisplayLabel: "Parent A",
        parentPaneOrdinal: 4,
        drawerOrdinal: 5,
        runtimeDisplayLabel: "Runtime A",
        activityBurstWindowId: "burst-action",
        activitySessionId: "activity-session-action",
        activityEventCount: 6,
        activityRowsAdded: 7,
        activityThresholdRows: 8,
        activityLatestRows: 9,
        claimPaneId: claimPaneId,
        claimLane: "actionNeeded",
        claimSemantic: "unseenActivity",
        claimSessionId: claimSessionId,
        isRead: true,
        isDismissedFromPaneInbox: false
    )
}

private func expectActivityNotificationPreserved(_ migratedRow: Row?, sessionId: String) {
    #expect(migratedRow?["claim_lane"] as String? == "activity")
    #expect(migratedRow?["claim_semantic"] as String? == "unseenActivity")
    #expect(migratedRow?["claim_session_id"] as String? == sessionId)
}

private func expectSafetyNotificationPreserved(_ migratedRow: Row?, claimPaneId: String) {
    #expect(migratedRow?["claim_pane_id"] as String? == claimPaneId)
    #expect(migratedRow?["claim_lane"] as String? == "safety")
    #expect(migratedRow?["claim_semantic"] as String? == "securityEvent")
    #expect(migratedRow?["claim_session_id"] as String? == nil)
}

private func expectActionNeededNotificationPreserved(
    _ migratedRow: Row?,
    claimPaneId: String,
    claimSessionId: String
) {
    let expectedStringValues = [
        ("kind", "action"),
        ("title", "Action needed"),
        ("body", "Review required"),
        ("source_kind", "agent"),
        ("pane_id", "pane-action"),
        ("tab_id", "tab-action"),
        ("tab_display_label", "Tab A"),
        ("repo_id", "repo-action"),
        ("repo_name", "agentstudio"),
        ("worktree_id", "worktree-action"),
        ("worktree_name", "feature/sqlite"),
        ("branch_name", "sqlite"),
        ("pane_display_label", "Pane A"),
        ("pane_role", "terminal"),
        ("parent_pane_id", "parent-pane-action"),
        ("parent_pane_display_label", "Parent A"),
        ("runtime_display_label", "Runtime A"),
        ("activity_burst_window_id", "burst-action"),
        ("activity_session_id", "activity-session-action"),
        ("claim_pane_id", claimPaneId),
        ("claim_lane", "actionNeeded"),
        ("claim_semantic", "unseenActivity"),
        ("claim_session_id", claimSessionId),
    ]
    let expectedIntegerValues = [
        ("tab_ordinal", 2),
        ("pane_ordinal", 3),
        ("parent_pane_ordinal", 4),
        ("drawer_ordinal", 5),
        ("activity_event_count", 6),
        ("activity_rows_added", 7),
        ("activity_threshold_rows", 8),
        ("activity_latest_rows", 9),
        ("is_read", 1),
        ("is_dismissed_from_pane_inbox", 0),
    ]

    #expect(migratedRow?["timestamp"] as Double? == 11.5)
    #expect(migratedRow?["pane_id"] as String? != migratedRow?["claim_pane_id"] as String?)
    for (columnName, expectedValue) in expectedStringValues {
        #expect(migratedRow?[columnName] as String? == expectedValue)
    }
    for (columnName, expectedValue) in expectedIntegerValues {
        #expect(migratedRow?[columnName] as Int? == expectedValue)
    }
}

private func expectMalformedClaimsNormalized(
    _ migratedRowsById: [String: Row],
    fixture: LegacyNotificationClaimMigrationFixture
) {
    #expect(migratedRowsById[fixture.unknownLaneId]?["claim_pane_id"] as String? == nil)
    #expect(migratedRowsById[fixture.unknownLaneId]?["claim_lane"] as String? == nil)
    #expect(migratedRowsById[fixture.unknownLaneId]?["claim_semantic"] as String? == nil)
    #expect(migratedRowsById[fixture.partialClaimId]?["claim_pane_id"] as String? == nil)
    #expect(migratedRowsById[fixture.partialClaimId]?["claim_lane"] as String? == nil)
    #expect(migratedRowsById[fixture.partialClaimId]?["claim_semantic"] as String? == nil)
    #expect(migratedRowsById[fixture.sessionOnlyId]?["claim_session_id"] as String? == nil)
}

private struct LegacyNotificationRecord {
    let workspaceId: String
    let id: String
    var timestamp = 1.0
    var kind = "activity"
    var title = "Terminal activity"
    var body: String?
    var sourceKind = "terminal"
    var paneId: String?
    var tabId: String?
    var tabDisplayLabel: String?
    var tabOrdinal: Int?
    var repoId: String?
    var repoName: String?
    var worktreeId: String?
    var worktreeName: String?
    var branchName: String?
    var paneDisplayLabel: String?
    var paneOrdinal: Int?
    var paneRole: String?
    var parentPaneId: String?
    var parentPaneDisplayLabel: String?
    var parentPaneOrdinal: Int?
    var drawerOrdinal: Int?
    var runtimeDisplayLabel: String?
    var activityBurstWindowId: String?
    var activitySessionId: String?
    var activityEventCount: Int?
    var activityRowsAdded: Int?
    var activityThresholdRows: Int?
    var activityLatestRows: Int?
    let claimPaneId: String?
    let claimLane: String?
    let claimSemantic: String?
    let claimSessionId: String?
    var isRead = false
    var isDismissedFromPaneInbox = false
}

private func insertLegacyNotification(_ database: Database, record: LegacyNotificationRecord) throws {
    try database.execute(
        sql: """
            INSERT INTO local_notification_inbox_item(
                id, workspace_id, timestamp, kind, title, body, source_kind,
                pane_id, tab_id, tab_display_label, tab_ordinal,
                repo_id, repo_name, worktree_id, worktree_name, branch_name,
                pane_display_label, pane_ordinal, pane_role,
                parent_pane_id, parent_pane_display_label, parent_pane_ordinal,
                drawer_ordinal, runtime_display_label,
                activity_burst_window_id, activity_session_id, activity_event_count,
                activity_rows_added, activity_threshold_rows, activity_latest_rows,
                claim_pane_id, claim_lane, claim_semantic, claim_session_id,
                is_read, is_dismissed_from_pane_inbox
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
        arguments: [
            record.id,
            record.workspaceId,
            record.timestamp,
            record.kind,
            record.title,
            record.body,
            record.sourceKind,
            record.paneId,
            record.tabId,
            record.tabDisplayLabel,
            record.tabOrdinal,
            record.repoId,
            record.repoName,
            record.worktreeId,
            record.worktreeName,
            record.branchName,
            record.paneDisplayLabel,
            record.paneOrdinal,
            record.paneRole,
            record.parentPaneId,
            record.parentPaneDisplayLabel,
            record.parentPaneOrdinal,
            record.drawerOrdinal,
            record.runtimeDisplayLabel,
            record.activityBurstWindowId,
            record.activitySessionId,
            record.activityEventCount,
            record.activityRowsAdded,
            record.activityThresholdRows,
            record.activityLatestRows,
            record.claimPaneId,
            record.claimLane,
            record.claimSemantic,
            record.claimSessionId,
            record.isRead ? 1 : 0,
            record.isDismissedFromPaneInbox ? 1 : 0,
        ]
    )
}

private func createLegacyNotificationInboxItemBeforeClaimKeyEnforcement(_ database: Database) throws {
    try database.execute(
        sql: """
            CREATE TABLE local_notification_inbox_item (
                id TEXT PRIMARY KEY,
                workspace_id TEXT NOT NULL,
                timestamp REAL NOT NULL,
                kind TEXT NOT NULL,
                title TEXT NOT NULL,
                body TEXT,
                source_kind TEXT NOT NULL,
                pane_id TEXT,
                tab_id TEXT,
                tab_display_label TEXT,
                tab_ordinal INTEGER,
                repo_id TEXT,
                repo_name TEXT,
                worktree_id TEXT,
                worktree_name TEXT,
                branch_name TEXT,
                pane_display_label TEXT,
                pane_ordinal INTEGER,
                pane_role TEXT,
                parent_pane_id TEXT,
                parent_pane_display_label TEXT,
                parent_pane_ordinal INTEGER,
                drawer_ordinal INTEGER,
                runtime_display_label TEXT,
                activity_burst_window_id TEXT,
                activity_session_id TEXT,
                activity_event_count INTEGER,
                activity_rows_added INTEGER,
                activity_threshold_rows INTEGER,
                activity_latest_rows INTEGER,
                claim_pane_id TEXT,
                claim_lane TEXT,
                claim_semantic TEXT,
                claim_session_id TEXT,
                is_read INTEGER NOT NULL CHECK (is_read IN (0, 1)),
                is_dismissed_from_pane_inbox INTEGER NOT NULL CHECK (
                    is_dismissed_from_pane_inbox IN (0, 1)
                )
            )
            """
    )
}

private func markCompletedLocalMigrationsBeforeClaimKeyEnforcement(_ database: Database) throws {
    try database.execute(
        sql: """
            CREATE TABLE grdb_migrations (
                identifier TEXT NOT NULL PRIMARY KEY
            )
            """
    )
    for migrationId in [
        "002_create_local_workspace_memory",
        "003_create_local_notifications",
        "004_create_cache_tables",
    ] {
        try database.execute(
            sql: """
                INSERT INTO grdb_migrations(identifier)
                VALUES (?)
                """,
            arguments: [migrationId]
        )
    }
}
