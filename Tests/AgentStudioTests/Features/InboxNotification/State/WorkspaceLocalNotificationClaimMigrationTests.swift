import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("WorkspaceLocalNotificationClaimMigrationTests")
struct WorkspaceLocalNotificationClaimMigrationTests {
    @Test("partial malformed and unsupported notification claims disappear physically")
    func partialMalformedAndUnsupportedNotificationClaimsDisappearPhysically() throws {
        let fixture = try makeNotificationClaimFixture()
        let paneId = UUID().uuidString
        let sessionId = UUID().uuidString
        let validLane = InboxNotificationClaimLane.activity.rawValue
        let validSemantic = InboxNotificationClaimSemantic.unseenActivity.rawValue
        let validPresenceMasks: Set<Int> = [0b0000, 0b0111, 0b1111]
        let partialClaims = (0..<16)
            .filter { !validPresenceMasks.contains($0) }
            .map { mask in
                (
                    pane: (mask & 0b0001) == 0 ? nil : paneId,
                    lane: (mask & 0b0010) == 0 ? nil : validLane,
                    semantic: (mask & 0b0100) == 0 ? nil : validSemantic,
                    session: (mask & 0b1000) == 0 ? nil : sessionId
                )
            }
        let malformedClaims =
            partialClaims + [
                (paneId, "futureLane", validSemantic, nil),
                (paneId, validLane, "futureSemantic", nil),
                ("not-a-uuid", validLane, validSemantic, nil),
                (paneId, validLane, validSemantic, "not-a-uuid"),
            ]
        for claim in malformedClaims {
            try insertRawNotification(
                fixture.databaseQueue,
                record: .init(
                    workspaceId: fixture.workspaceId,
                    id: UUID(),
                    claimPaneId: claim.pane,
                    claimLane: claim.lane,
                    claimSemantic: claim.semantic,
                    claimSessionId: claim.session
                )
            )
        }

        #expect(try fixture.repository.fetchNotifications().isEmpty)
        let physicalRowCount = try fixture.databaseQueue.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM local_notification_inbox_item WHERE workspace_id = ?",
                arguments: [fixture.workspaceId.uuidString]
            ) ?? -1
        }
        #expect(physicalRowCount == 0)
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
