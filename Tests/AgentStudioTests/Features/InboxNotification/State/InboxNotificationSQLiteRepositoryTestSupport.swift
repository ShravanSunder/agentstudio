import Foundation
import GRDB

@testable import AgentStudio

struct RawNotificationRow {
    let workspaceId: UUID
    let id: UUID
    let timestamp: Double
    let kind: String
    let title: String
    let sourceKind: String
    var paneId: UUID?
    var paneRole: String?
    var claimPaneId: UUID?
    var claimLane: String?
    var claimSemantic: String?
}

func insertRawNotificationRow(
    databaseQueue: DatabaseQueue,
    row: RawNotificationRow
) throws {
    try databaseQueue.write { database in
        try database.execute(
            sql: """
                INSERT INTO local_notification_inbox_item(
                    id, workspace_id, timestamp, kind, title, source_kind, pane_id, pane_role,
                    claim_pane_id, claim_lane, claim_semantic, is_read, is_dismissed_from_pane_inbox
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0)
                """,
            arguments: [
                row.id.uuidString,
                row.workspaceId.uuidString,
                row.timestamp,
                row.kind,
                row.title,
                row.sourceKind,
                row.paneId?.uuidString,
                row.paneRole,
                row.claimPaneId?.uuidString,
                row.claimLane,
                row.claimSemantic,
            ]
        )
    }
}
