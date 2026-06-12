import Foundation
import GRDB

struct InboxNotificationSQLiteRepository {
    struct RetentionOutcome: Sendable, Equatable {
        static let empty = Self(droppedCount: 0, droppedNotificationIds: [])

        let droppedCount: Int
        let droppedNotificationIds: [UUID]
    }

    struct MutationOutcome: Sendable, Equatable {
        let notificationId: UUID
        let didCoalesce: Bool
        let retentionOutcome: RetentionOutcome
    }

    let workspaceId: UUID
    let databaseWriter: any DatabaseWriter

    func replaceSnapshot(
        notifications: [InboxNotification],
        collapsedGroups: Set<InboxNotificationGroupKey>
    ) throws {
        try replaceSnapshot(
            notifications: notifications,
            collapsedGroups: collapsedGroups,
            markLegacyImport: false
        )
    }

    func replaceLegacyImportSnapshot(
        notifications: [InboxNotification],
        collapsedGroups: Set<InboxNotificationGroupKey>
    ) throws {
        try replaceSnapshot(
            notifications: notifications,
            collapsedGroups: collapsedGroups,
            markLegacyImport: true
        )
    }

    private func replaceSnapshot(
        notifications: [InboxNotification],
        collapsedGroups: Set<InboxNotificationGroupKey>,
        markLegacyImport: Bool
    ) throws {
        try databaseWriter.write { database in
            try deleteNotificationRows(database)
            for notification in notifications {
                try upsertNotificationRow(database, notification: notification)
            }
            _ = try enforceRetentionCap(database)
            try replaceCollapsedGroupRows(database, groups: collapsedGroups)
            try markPersistedState(database)
            if markLegacyImport {
                try markLegacyImportMaterialized(database)
            }
        }
    }

    func replaceAll(_ notifications: [InboxNotification]) throws {
        try databaseWriter.write { database in
            try deleteNotificationRows(database)
            for notification in notifications {
                try upsertNotificationRow(database, notification: notification)
            }
            _ = try enforceRetentionCap(database)
            try markPersistedState(database)
        }
    }

    func fetchNotifications() throws -> [InboxNotification] {
        try databaseWriter.read { database in
            try fetchNotificationRows(database).map(InboxNotificationSQLiteCodecs.notification(from:))
        }
    }

    func append(_ notification: InboxNotification) throws -> RetentionOutcome {
        try databaseWriter.write { database in
            try upsertNotificationRow(database, notification: notification)
            try markPersistedState(database)
            return try enforceRetentionCap(database)
        }
    }

    func upsertByClaim(
        _ notification: InboxNotification,
        merge: (InboxNotification, InboxNotification) -> InboxNotification
    ) throws -> MutationOutcome {
        try databaseWriter.write { database in
            if let existing = try coalescenceCandidate(database, for: notification) {
                let replacement = merge(existing, notification)
                try upsertNotificationRow(database, notification: replacement)
                try markPersistedState(database)
                return MutationOutcome(
                    notificationId: replacement.id,
                    didCoalesce: true,
                    retentionOutcome: .empty
                )
            }

            try upsertNotificationRow(database, notification: notification)
            try markPersistedState(database)
            return MutationOutcome(
                notificationId: notification.id,
                didCoalesce: false,
                retentionOutcome: try enforceRetentionCap(database)
            )
        }
    }

    func markRead(id: UUID) throws -> Bool {
        try updateNotification(id: id, setClause: "is_read = 1")
    }

    func markRead(paneId: UUID) throws {
        try databaseWriter.write { database in
            try database.execute(
                sql: """
                    UPDATE local_notification_inbox_item
                    SET is_read = 1
                    WHERE workspace_id = ? AND pane_id = ?
                    """,
                arguments: [workspaceId.uuidString, paneId.uuidString]
            )
        }
    }

    func markAllRead() throws {
        try databaseWriter.write { database in
            try database.execute(
                sql: """
                    UPDATE local_notification_inbox_item
                    SET is_read = 1
                    WHERE workspace_id = ?
                    """,
                arguments: [workspaceId.uuidString]
            )
        }
    }

    func dismissFromPaneInbox(id: UUID) throws -> Bool {
        try updateNotification(id: id, setClause: "is_dismissed_from_pane_inbox = 1")
    }

    func dismissFromPaneInbox(paneId: UUID) throws {
        try databaseWriter.write { database in
            try database.execute(
                sql: """
                    UPDATE local_notification_inbox_item
                    SET is_dismissed_from_pane_inbox = 1
                    WHERE workspace_id = ? AND pane_id = ?
                    """,
                arguments: [workspaceId.uuidString, paneId.uuidString]
            )
        }
    }

    func clearPaneInbox(paneIds: [UUID]) throws {
        try databaseWriter.write { database in
            for paneId in paneIds {
                try database.execute(
                    sql: """
                        UPDATE local_notification_inbox_item
                        SET is_read = 1, is_dismissed_from_pane_inbox = 1
                        WHERE workspace_id = ? AND pane_id = ?
                        """,
                    arguments: [workspaceId.uuidString, paneId.uuidString]
                )
            }
        }
    }

    func toggleReadState(id: UUID) throws -> Bool {
        try updateNotification(
            id: id,
            setClause: "is_read = CASE is_read WHEN 1 THEN 0 ELSE 1 END"
        )
    }

    func clearReadHistory() throws {
        try databaseWriter.write { database in
            try database.execute(
                sql: """
                    DELETE FROM local_notification_inbox_item
                    WHERE workspace_id = ? AND is_read = 1
                    """,
                arguments: [workspaceId.uuidString]
            )
            try markPersistedState(database)
        }
    }

    func clearAll() throws {
        try databaseWriter.write { database in
            try deleteNotificationRows(database)
            try markPersistedState(database)
        }
    }

    func replaceCollapsedGroups(_ groups: Set<InboxNotificationGroupKey>) throws {
        try databaseWriter.write { database in
            try replaceCollapsedGroupRows(database, groups: groups)
            try markPersistedState(database)
        }
    }

    func fetchCollapsedGroups() throws -> Set<InboxNotificationGroupKey> {
        let groupKeys = try databaseWriter.read { database in
            try String.fetchAll(
                database,
                sql: """
                        SELECT group_key
                        FROM local_notification_inbox_collapsed_group
                        WHERE workspace_id = ?
                    """,
                arguments: [workspaceId.uuidString]
            )
        }
        let collapsedGroups: Set<InboxNotificationGroupKey> = Set(
            groupKeys.map { rawValue in InboxNotificationGroupKey(rawValue) }
        )
        return collapsedGroups
    }

    func hasPersistedState() throws -> Bool {
        try databaseWriter.read { database in
            if try persistenceLaneExists(database) { return true }
            if try rowExists(database, table: "local_notification_inbox_item") { return true }
            return try rowExists(database, table: "local_notification_inbox_collapsed_group")
        }
    }

    func hasMaterializedLegacyImport() throws -> Bool {
        try databaseWriter.read { database in
            try persistenceLaneExists(database, lane: Self.legacyImportPersistenceLane)
        }
    }

    private func updateNotification(id: UUID, setClause: String) throws -> Bool {
        try databaseWriter.write { database in
            guard try notificationExists(database, id: id) else { return false }
            try database.execute(
                sql: """
                    UPDATE local_notification_inbox_item
                    SET \(setClause)
                    WHERE workspace_id = ? AND id = ?
                    """,
                arguments: [workspaceId.uuidString, id.uuidString]
            )
            return true
        }
    }

    private func notificationExists(_ database: Database, id: UUID) throws -> Bool {
        let exists = try Int.fetchOne(
            database,
            sql: """
                SELECT 1
                FROM local_notification_inbox_item
                WHERE workspace_id = ? AND id = ?
                LIMIT 1
                """,
            arguments: [workspaceId.uuidString, id.uuidString]
        )
        return exists != nil
    }

    private func coalescenceCandidate(
        _ database: Database,
        for incoming: InboxNotification
    ) throws -> InboxNotification? {
        guard let claimKey = incoming.claimKey else { return nil }
        if let exactCandidate = try exactCoalescenceCandidate(
            database,
            claimKey: claimKey,
            incoming: incoming
        ) {
            return exactCandidate
        }
        return try sessionCoalescenceCandidate(
            database,
            claimKey: claimKey,
            incoming: incoming
        )
    }

    private func exactCoalescenceCandidate(
        _ database: Database,
        claimKey: InboxNotificationClaimKey,
        incoming: InboxNotification
    ) throws -> InboxNotification? {
        guard claimKey.lane.canMergeWithinActivitySession else { return nil }
        let rows = try Row.fetchAll(
            database,
            sql: """
                SELECT *
                FROM local_notification_inbox_item
                WHERE workspace_id = ?
                    AND claim_pane_id = ?
                    AND claim_lane = ?
                    AND claim_semantic = ?
                    AND (
                        (? IS NULL AND claim_session_id IS NULL)
                        OR claim_session_id = ?
                    )
                ORDER BY rowid
                """,
            arguments: [
                workspaceId.uuidString,
                claimKey.paneId.uuidString,
                claimKey.lane.rawValue,
                claimKey.semantic.rawValue,
                claimKey.sessionId?.uuidString,
                claimKey.sessionId?.uuidString,
            ]
        )
        let candidates = try rows.map(InboxNotificationSQLiteCodecs.notification(from:))
        return candidates.first { existing in
            existing.claimKey == claimKey
                && InboxNotificationClaimCoalescence.canCoalesce(existing: existing, incoming: incoming)
        }
    }

    private func sessionCoalescenceCandidate(
        _ database: Database,
        claimKey: InboxNotificationClaimKey,
        incoming: InboxNotification
    ) throws -> InboxNotification? {
        guard
            let sessionId = claimKey.sessionId,
            claimKey.lane.canMergeWithinActivitySession
        else { return nil }
        let rows = try Row.fetchAll(
            database,
            sql: """
                SELECT *
                FROM local_notification_inbox_item
                WHERE workspace_id = ?
                    AND claim_pane_id = ?
                    AND claim_session_id = ?
                    AND claim_lane IN (\(SQLiteInboxNotificationClaimStorage.mergeableLaneSQLValues))
                ORDER BY rowid
                """,
            arguments: [
                workspaceId.uuidString,
                claimKey.paneId.uuidString,
                sessionId.uuidString,
            ]
        )
        let candidates = try rows.map(InboxNotificationSQLiteCodecs.notification(from:))
        return candidates.first { existing in
            guard let existingClaimKey = existing.claimKey else { return false }
            return existingClaimKey.paneId == claimKey.paneId
                && existingClaimKey.sessionId == sessionId
                && existingClaimKey.lane.canMergeWithinActivitySession
                && InboxNotificationClaimCoalescence.canCoalesce(existing: existing, incoming: incoming)
        }
    }

    private func fetchNotificationRows(_ database: Database) throws -> [Row] {
        try Row.fetchAll(
            database,
            sql: """
                SELECT *
                FROM local_notification_inbox_item
                WHERE workspace_id = ?
                ORDER BY rowid
                """,
            arguments: [workspaceId.uuidString]
        )
    }

    private func deleteNotificationRows(_ database: Database) throws {
        try database.execute(
            sql: """
                DELETE FROM local_notification_inbox_item
                WHERE workspace_id = ?
                """,
            arguments: [workspaceId.uuidString]
        )
    }

    private func replaceCollapsedGroupRows(
        _ database: Database,
        groups: Set<InboxNotificationGroupKey>
    ) throws {
        try database.execute(
            sql: """
                DELETE FROM local_notification_inbox_collapsed_group
                WHERE workspace_id = ?
                """,
            arguments: [workspaceId.uuidString]
        )
        for group in groups {
            try database.execute(
                sql: """
                    INSERT INTO local_notification_inbox_collapsed_group(workspace_id, group_key)
                    VALUES (?, ?)
                    """,
                arguments: [workspaceId.uuidString, group.rawValue]
            )
        }
    }

    private func upsertNotificationRow(
        _ database: Database,
        notification: InboxNotification
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO local_notification_inbox_item (
                    id,
                    workspace_id,
                    timestamp,
                    kind,
                    title,
                    body,
                    source_kind,
                    pane_id,
                    tab_id,
                    tab_display_label,
                    tab_ordinal,
                    repo_id,
                    repo_name,
                    worktree_id,
                    worktree_name,
                    branch_name,
                    pane_display_label,
                    pane_ordinal,
                    pane_role,
                    parent_pane_id,
                    parent_pane_display_label,
                    parent_pane_ordinal,
                    drawer_ordinal,
                    runtime_display_label,
                    activity_burst_window_id,
                    activity_session_id,
                    activity_event_count,
                    activity_rows_added,
                    activity_threshold_rows,
                    activity_latest_rows,
                    claim_pane_id,
                    claim_lane,
                    claim_semantic,
                    claim_session_id,
                    is_read,
                    is_dismissed_from_pane_inbox
                )
                VALUES (
                    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
                )
                ON CONFLICT(id) DO UPDATE SET
                    workspace_id = excluded.workspace_id,
                    timestamp = excluded.timestamp,
                    kind = excluded.kind,
                    title = excluded.title,
                    body = excluded.body,
                    source_kind = excluded.source_kind,
                    pane_id = excluded.pane_id,
                    tab_id = excluded.tab_id,
                    tab_display_label = excluded.tab_display_label,
                    tab_ordinal = excluded.tab_ordinal,
                    repo_id = excluded.repo_id,
                    repo_name = excluded.repo_name,
                    worktree_id = excluded.worktree_id,
                    worktree_name = excluded.worktree_name,
                    branch_name = excluded.branch_name,
                    pane_display_label = excluded.pane_display_label,
                    pane_ordinal = excluded.pane_ordinal,
                    pane_role = excluded.pane_role,
                    parent_pane_id = excluded.parent_pane_id,
                    parent_pane_display_label = excluded.parent_pane_display_label,
                    parent_pane_ordinal = excluded.parent_pane_ordinal,
                    drawer_ordinal = excluded.drawer_ordinal,
                    runtime_display_label = excluded.runtime_display_label,
                    activity_burst_window_id = excluded.activity_burst_window_id,
                    activity_session_id = excluded.activity_session_id,
                    activity_event_count = excluded.activity_event_count,
                    activity_rows_added = excluded.activity_rows_added,
                    activity_threshold_rows = excluded.activity_threshold_rows,
                    activity_latest_rows = excluded.activity_latest_rows,
                    claim_pane_id = excluded.claim_pane_id,
                    claim_lane = excluded.claim_lane,
                    claim_semantic = excluded.claim_semantic,
                    claim_session_id = excluded.claim_session_id,
                    is_read = excluded.is_read,
                    is_dismissed_from_pane_inbox = excluded.is_dismissed_from_pane_inbox
                """,
            arguments: InboxNotificationSQLiteCodecs.arguments(
                workspaceId: workspaceId,
                notification: notification
            )
        )
    }

    private func enforceRetentionCap(_ database: Database) throws -> RetentionOutcome {
        let count =
            try Int.fetchOne(
                database,
                sql: """
                    SELECT COUNT(*)
                    FROM local_notification_inbox_item
                    WHERE workspace_id = ?
                    """,
                arguments: [workspaceId.uuidString]
            ) ?? 0
        let overflow = count - AppPolicies.InboxNotification.maxRetained
        guard overflow > 0 else { return .empty }

        let droppedIds = try String.fetchAll(
            database,
            sql: """
                SELECT id
                FROM local_notification_inbox_item
                WHERE workspace_id = ?
                ORDER BY timestamp, id
                LIMIT ?
                """,
            arguments: [workspaceId.uuidString, overflow]
        )
        if !droppedIds.isEmpty {
            let placeholders = Array(repeating: "?", count: droppedIds.count).joined(separator: ", ")
            try database.execute(
                sql: """
                    DELETE FROM local_notification_inbox_item
                    WHERE workspace_id = ? AND id IN (\(placeholders))
                    """,
                arguments: StatementArguments([workspaceId.uuidString] + droppedIds)
            )
        }

        return .init(
            droppedCount: droppedIds.count,
            droppedNotificationIds: try droppedIds.map {
                try InboxNotificationSQLiteCodecs.uuid(
                    $0,
                    InboxNotificationSQLiteRepositoryError.malformedNotificationId
                )
            }
        )
    }

    private func markPersistedState(_ database: Database) throws {
        try markPersistenceLane(database, lane: Self.persistenceLane)
    }

    private func markLegacyImportMaterialized(_ database: Database) throws {
        try markPersistenceLane(database, lane: Self.legacyImportPersistenceLane)
    }

    private func markPersistenceLane(_ database: Database, lane: String) throws {
        try database.execute(
            sql: """
                INSERT INTO local_persistence_lane_marker(workspace_id, lane, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(workspace_id, lane) DO UPDATE SET
                    updated_at = excluded.updated_at
                """,
            arguments: [
                workspaceId.uuidString,
                lane,
                Date().timeIntervalSince1970,
            ]
        )
    }

    private func persistenceLaneExists(_ database: Database) throws -> Bool {
        try persistenceLaneExists(database, lane: Self.persistenceLane)
    }

    private func persistenceLaneExists(_ database: Database, lane: String) throws -> Bool {
        let count =
            try Int.fetchOne(
                database,
                sql: """
                    SELECT count(*)
                    FROM local_persistence_lane_marker
                    WHERE workspace_id = ? AND lane = ?
                    """,
                arguments: [workspaceId.uuidString, lane]
            ) ?? 0
        return count > 0
    }

    private func rowExists(_ database: Database, table: String) throws -> Bool {
        let count =
            try Int.fetchOne(
                database,
                sql: "SELECT count(*) FROM \(table) WHERE workspace_id = ? LIMIT 1",
                arguments: [workspaceId.uuidString]
            ) ?? 0
        return count > 0
    }

    private static let persistenceLane = "notification_inbox"
    private static let legacyImportPersistenceLane = "notification_inbox_legacy_import"
}

enum InboxNotificationSQLiteRepositoryError: Error, Equatable {
    case malformedNotificationId(String)
    case malformedPaneId(String)
    case malformedTabId(String)
    case malformedRepoId(String)
    case malformedWorktreeId(String)
    case malformedActivityBurstWindowId(String)
    case malformedActivitySessionId(String)
    case malformedClaimSessionId(String)
    case unsupportedNotificationKind(String)
    case unsupportedSourceKind(String)
    case unsupportedPaneRole(String)
    case unsupportedClaimLane(String)
    case unsupportedClaimSemantic(String)
    case malformedActivityContext(UUID)
    case malformedClaimKey(UUID)
    case missingPaneId(UUID)
}
