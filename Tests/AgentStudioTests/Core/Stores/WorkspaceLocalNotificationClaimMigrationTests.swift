import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("WorkspaceLocalNotificationClaimMigrationTests")
struct WorkspaceLocalNotificationClaimMigrationTests {
    @Test("session-only notification claim disappears")
    func sessionOnlyNotificationClaimDisappears() throws {
        let fixture = try makeNotificationClaimFixture()
        try insertRawNotification(
            fixture.databaseQueue,
            record: .init(
                workspaceId: fixture.workspaceId,
                id: UUID(),
                claimPaneId: nil,
                claimLane: nil,
                claimSemantic: nil,
                claimSessionId: UUID().uuidString
            )
        )

        #expect(try fixture.repository.fetchNotifications().isEmpty)
    }

    @Test("all typed notification claim lanes decode from the clean schema")
    func allTypedNotificationClaimLanesDecodeFromTheCleanSchema() throws {
        let fixture = try makeNotificationClaimFixture()
        let paneId = UUID()
        for lane in InboxNotificationClaimLane.allCases {
            try insertRawNotification(
                fixture.databaseQueue,
                record: .init(
                    workspaceId: fixture.workspaceId,
                    id: UUID(),
                    claimPaneId: paneId.uuidString,
                    claimLane: SQLiteInboxNotificationClaimStorage.storageValue(for: lane),
                    claimSemantic: InboxNotificationClaimSemantic.unseenActivity.rawValue,
                    claimSessionId: UUID().uuidString
                )
            )
        }

        let restoredLanes = try Set(fixture.repository.fetchNotifications().compactMap { $0.claimKey?.lane })
        #expect(restoredLanes == Set(InboxNotificationClaimLane.allCases))
    }
}

private struct NotificationClaimFixture {
    let workspaceId: UUID
    let databaseQueue: DatabaseQueue
    let repository: InboxNotificationSQLiteRepository
}

private struct RawNotificationClaimRecord {
    let workspaceId: UUID
    let id: UUID
    let claimPaneId: String?
    let claimLane: String?
    let claimSemantic: String?
    let claimSessionId: String?
}

private func makeNotificationClaimFixture() throws -> NotificationClaimFixture {
    let workspaceId = UUID()
    let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
    try WorkspaceLocalMigrations.migrate(databaseQueue)
    return .init(
        workspaceId: workspaceId,
        databaseQueue: databaseQueue,
        repository: InboxNotificationSQLiteRepository(workspaceId: workspaceId, databaseWriter: databaseQueue)
    )
}

private func insertRawNotification(
    _ databaseQueue: DatabaseQueue,
    record: RawNotificationClaimRecord
) throws {
    try databaseQueue.write { database in
        try database.execute(
            sql: """
                    INSERT INTO local_notification_inbox_item(
                        workspace_id, id, timestamp, kind, title, source_kind,
                        claim_pane_id, claim_lane, claim_semantic, claim_session_id,
                        is_read, is_dismissed_from_pane_inbox
                    ) VALUES (?, ?, 1, 'unseenActivity', 'Activity', 'global', ?, ?, ?, ?, 0, 0)
                """,
            arguments: [
                record.workspaceId.uuidString,
                record.id.uuidString,
                record.claimPaneId,
                record.claimLane,
                record.claimSemantic,
                record.claimSessionId,
            ]
        )
    }
}
