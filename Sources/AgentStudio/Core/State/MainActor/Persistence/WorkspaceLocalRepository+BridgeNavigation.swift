import Foundation
import GRDB

extension WorkspaceLocalRepository {
    func fetchBridgeNavigationRows() throws -> [BridgeNavigationRow] {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.fetchBridgeNavigationRows(database, workspaceId: workspaceId)
        }
    }

    /// Commit imported rows without ever overwriting an existing receiver row.
    /// Returns the receiver panes whose row is present after the commit.
    func insertBridgeNavigationRowsIfAbsent(
        _ rows: [BridgeNavigationRow],
        updatedAt: Date
    ) throws -> Set<UUID> {
        try databaseWriter.write { database in
            for row in rows {
                try database.execute(
                    sql: """
                        INSERT OR IGNORE INTO local_bridge_navigation(
                            workspace_id, receiver_pane_id, receiver_kind,
                            payload_version, payload_json, updated_at
                        ) VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        workspaceId.uuidString,
                        row.receiver.paneId.uuidString,
                        row.receiver.kind.rawValue,
                        row.payloadVersion,
                        row.payloadJSON,
                        updatedAt.timeIntervalSince1970,
                    ]
                )
            }
            let present = try WorkspaceLocalRepositoryStorage.fetchBridgeNavigationRows(
                database,
                workspaceId: workspaceId
            )
            return Set(present.map(\.receiver.paneId))
        }
    }
}

extension WorkspaceLocalRepositoryStorage {
    /// Replace the workspace's navigation rows with exactly `rows`. Rows for
    /// receivers that are neither live nor retained by available undo were
    /// already filtered out by the caller, which makes them eligible cleanup.
    static func replaceBridgeNavigationRows(
        _ database: Database,
        workspaceId: UUID,
        rows: [BridgeNavigationRow],
        updatedAt: Date
    ) throws {
        try database.execute(
            sql: "DELETE FROM local_bridge_navigation WHERE workspace_id = ?",
            arguments: [workspaceId.uuidString]
        )
        for row in rows {
            try database.execute(
                sql: """
                    INSERT INTO local_bridge_navigation(
                        workspace_id, receiver_pane_id, receiver_kind,
                        payload_version, payload_json, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    workspaceId.uuidString,
                    row.receiver.paneId.uuidString,
                    row.receiver.kind.rawValue,
                    row.payloadVersion,
                    row.payloadJSON,
                    updatedAt.timeIntervalSince1970,
                ]
            )
        }
    }

    static func fetchBridgeNavigationRows(
        _ database: Database,
        workspaceId: UUID
    ) throws -> [BridgeNavigationRow] {
        let rows = try Row.fetchAll(
            database,
            sql: """
                SELECT receiver_pane_id, receiver_kind, payload_version, payload_json
                FROM local_bridge_navigation
                WHERE workspace_id = ?
                ORDER BY receiver_pane_id
                """,
            arguments: [workspaceId.uuidString]
        )
        return try rows.map { row in
            let paneId = try WorkspaceLocalRepositoryCodecs.uuid(
                row["receiver_pane_id"],
                WorkspaceLocalRepositoryError.malformedPaneId
            )
            let kindValue: String = row["receiver_kind"]
            guard let kind = BridgeReceiverKind(rawValue: kindValue) else {
                throw WorkspaceLocalRepositoryError.malformedBridgeReceiverKind(kindValue)
            }
            return BridgeNavigationRow(
                receiver: BridgeReceiver(paneId: paneId, kind: kind),
                payloadVersion: row["payload_version"],
                payloadJSON: row["payload_json"]
            )
        }
    }
}
