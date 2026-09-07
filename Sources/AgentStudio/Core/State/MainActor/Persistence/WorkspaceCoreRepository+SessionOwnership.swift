import Foundation
import GRDB

/// Resolve release eligibility after all selected undo entries have finished, within their transaction.
func readUndoCloseRetirement(rawCloseID: String, database: Database) throws -> WorkspaceUndoCloseRetirement {
    guard let closeID = UUID(uuidString: rawCloseID) else { throw WorkspaceUndoJournalFailure.invalidStoredIdentifier }
    let members = try readUndoCloseMembers(closeID: closeID, database: database)
    var unownedPaneIDs = Set<UUID>()
    for member in members {
        let isOwned =
            try Bool.fetchOne(
                database,
                sql: """
                    SELECT EXISTS (SELECT 1 FROM pane WHERE id = ?)
                        OR EXISTS (
                            SELECT 1 FROM workspace_undo_close_member AS member
                            JOIN workspace_undo_close AS operation ON operation.close_id = member.close_id
                            WHERE member.pane_id = ? AND operation.state = 'available'
                        )
                    """, arguments: [member.paneID.uuidString, member.paneID.uuidString]) ?? true
        if !isOwned { unownedPaneIDs.insert(member.paneID) }
    }
    return .init(closeID: closeID, members: members, unownedPaneIDs: unownedPaneIDs)
}

extension WorkspaceCoreRepository {
    func nextUndoDeadline(bootID: String) throws -> Int64? {
        try databaseWriter.read { database in
            try Int64.fetchOne(
                database,
                sql: """
                    SELECT min(deadline_uptime_ns) FROM workspace_undo_close
                    WHERE state = 'available' AND deadline_boot_id = ?
                    """, arguments: [bootID])
        }
    }

    func workspaceIDsWithAvailableUndo() throws -> [UUID] {
        try databaseWriter.read { database in
            try String.fetchAll(
                database,
                sql:
                    "SELECT DISTINCT workspace_id FROM workspace_undo_close WHERE state = 'available' ORDER BY workspace_id"
            )
            .map { rawID in
                guard let workspaceID = UUID(uuidString: rawID) else {
                    throw WorkspaceUndoJournalFailure.invalidStoredIdentifier
                }
                return workspaceID
            }
        }
    }

    func reconcileUnownedTerminalSessions(at time: WorkspaceUndoJournalTime) throws {
        try validateUndoJournalTime(time)
        try databaseWriter.write { database in
            try markUnownedTerminalSessionsForCleanup(database, finishedUndoWorkspaceID: nil, requestedAt: time.utc)
        }
    }

    func pendingTerminalSessionIDs() throws -> Set<ZmxSessionID> {
        try databaseWriter.read { database in
            Set(
                try String.fetchAll(
                    database,
                    sql: "SELECT session_id FROM workspace_terminal_session_ownership WHERE cleanup_state = 'pending'"
                )
                .map { rawID in
                    guard let sessionID = ZmxSessionID(restoring: rawID) else {
                        throw WorkspaceUndoJournalFailure.invalidStoredIdentifier
                    }
                    return sessionID
                })
        }
    }
}

func markUnownedTerminalSessionsForCleanup(
    _ database: Database,
    finishedUndoWorkspaceID: UUID?,
    requestedAt: Date
) throws {
    try database.execute(
        sql: """
            UPDATE workspace_terminal_session_ownership
            SET cleanup_state = 'pending', cleanup_requested_at = ?
            WHERE cleanup_state = 'owned'
                AND (? IS NULL OR session_id IN (
                    SELECT member.session_id FROM workspace_undo_close_member AS member
                    JOIN workspace_undo_close AS operation ON operation.close_id = member.close_id
                    WHERE operation.workspace_id = ? AND operation.state IN ('evicted', 'expired', 'restored')
                ))
                AND NOT EXISTS (
                    SELECT 1 FROM pane_content_terminal AS terminal
                    WHERE terminal.zmx_session_id = workspace_terminal_session_ownership.session_id
                )
                AND NOT EXISTS (
                    SELECT 1 FROM workspace_undo_close_member AS member
                    JOIN workspace_undo_close AS operation ON operation.close_id = member.close_id
                    WHERE member.session_id = workspace_terminal_session_ownership.session_id
                        AND operation.state = 'available'
                )
            """,
        arguments: [
            requestedAt.timeIntervalSince1970, finishedUndoWorkspaceID?.uuidString, finishedUndoWorkspaceID?.uuidString,
        ]
    )
}
