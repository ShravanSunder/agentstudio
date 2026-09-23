import Foundation
import GRDB

extension WorkspaceCoreRepository {
    /// Stored `bridgePanel` payloads of the workspace's live panes, read for the
    /// ordered legacy-source conversion.
    func fetchBridgePanePayloads(workspaceID: UUID) throws -> [(paneID: UUID, payloadJSON: String)] {
        try databaseWriter.read { database in
            try Row.fetchAll(
                database,
                sql: """
                    SELECT payload.pane_id, payload.payload_json
                    FROM pane_content_payload AS payload
                    JOIN pane ON pane.id = payload.pane_id
                    WHERE pane.workspace_id = ? AND payload.payload_kind = 'bridgePanel'
                    ORDER BY payload.pane_id
                    """,
                arguments: [workspaceID.uuidString]
            ).map { row in
                let paneIDString: String = row["pane_id"]
                guard let paneID = UUID(uuidString: paneIDString) else {
                    throw WorkspaceCoreRepositoryError.malformedPaneId(paneIDString)
                }
                return (paneID, row["payload_json"])
            }
        }
    }

    func fetchLivePaneIDs(workspaceID: UUID) throws -> Set<UUID> {
        try databaseWriter.read { database in
            let paneIDStrings = try String.fetchAll(
                database,
                sql: "SELECT id FROM pane WHERE workspace_id = ?",
                arguments: [workspaceID.uuidString]
            )
            return Set(paneIDStrings.compactMap(UUID.init(uuidString:)))
        }
    }

    /// Pane identities retained by available durable undo. Their receiver
    /// navigation rows stay eligible until the undo expires.
    func fetchAvailableUndoMemberPaneIDs(workspaceID: UUID) throws -> Set<UUID> {
        try databaseWriter.read { database in
            let paneIDStrings = try String.fetchAll(
                database,
                sql: """
                    SELECT member.pane_id
                    FROM workspace_undo_close_member AS member
                    JOIN workspace_undo_close AS close ON close.close_id = member.close_id
                    WHERE close.workspace_id = ? AND close.state = 'available'
                    """,
                arguments: [workspaceID.uuidString]
            )
            return Set(paneIDStrings.compactMap(UUID.init(uuidString:)))
        }
    }

    /// The core step of the ordered conversion: replace a still-legacy payload
    /// with its source-free form. Runs only after the imported local record is
    /// committed and acknowledged; a payload that changed meanwhile is left alone.
    @discardableResult
    func rewriteLegacyBridgePanePayload(
        paneID: UUID,
        expectedPayloadJSON: String,
        convertedPayloadJSON: String
    ) throws -> Bool {
        try databaseWriter.write { database in
            try database.execute(
                sql: """
                    UPDATE pane_content_payload
                    SET payload_json = ?
                    WHERE pane_id = ? AND payload_kind = 'bridgePanel' AND payload_json = ?
                    """,
                arguments: [convertedPayloadJSON, paneID.uuidString, expectedPayloadJSON]
            )
            return database.changesCount == 1
        }
    }
}
