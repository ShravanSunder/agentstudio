import AgentStudioInfrastructure
import Foundation
import GRDB

/// Executes inside the same transaction as the workspace composition replacement.
func writeUndoClose(_ close: WorkspaceUndoCloseWrite, in database: Database) throws {
    let previousSequence =
        try Int64.fetchOne(
            database,
            sql: "SELECT COALESCE(MAX(close_sequence), 0) FROM workspace_undo_close WHERE workspace_id = ?",
            arguments: [close.workspaceID.uuidString]
        ) ?? 0
    let (sequence, overflow) = previousSequence.addingReportingOverflow(1)
    guard !overflow else { throw WorkspaceUndoCloseWriteFailure.sequenceExhausted }

    try database.execute(
        sql: """
            INSERT INTO workspace_undo_close(
                close_id, workspace_id, close_sequence, close_kind, closed_at, expires_at,
                state, snapshot_version, snapshot_payload, deadline_boot_id, deadline_uptime_ns
            ) VALUES (?, ?, ?, ?, ?, ?, 'available', ?, ?, ?, ?)
            """,
        arguments: [
            close.closeID.uuidString,
            close.workspaceID.uuidString,
            sequence,
            close.kind.rawValue,
            close.closedAt.timeIntervalSince1970,
            close.expiresAt.timeIntervalSince1970,
            close.snapshotVersion,
            close.snapshotPayload,
            close.deadlineBootID,
            close.deadlineUptimeNanoseconds,
        ]
    )
    for member in close.members {
        if let sessionID = member.sessionID {
            try database.execute(
                sql: """
                    INSERT INTO workspace_terminal_session_ownership(session_id) VALUES (?)
                    ON CONFLICT(session_id) DO NOTHING
                    """,
                arguments: [sessionID.rawValue]
            )
        }
        try database.execute(
            sql: """
                INSERT INTO workspace_undo_close_member(close_id, pane_id, session_id) VALUES (?, ?, ?)
                """,
            arguments: [close.closeID.uuidString, member.paneID.uuidString, member.sessionID?.rawValue]
        )
    }

    try database.execute(
        sql: """
            UPDATE workspace_undo_close SET state = 'evicted'
            WHERE close_id IN (
                SELECT close_id FROM workspace_undo_close
                WHERE workspace_id = ? AND state = 'available'
                ORDER BY close_sequence DESC LIMIT -1 OFFSET ?
            )
            """,
        arguments: [close.workspaceID.uuidString, AppPolicies.WorkspacePersistence.maximumAvailableUndoCloses]
    )
    try markFinishedUndoSessionsForCleanup(
        database,
        workspaceID: close.workspaceID,
        requestedAt: close.closedAt
    )
}

func markFinishedUndoSessionsForCleanup(
    _ database: Database,
    workspaceID: UUID,
    requestedAt: Date
) throws {
    try database.execute(
        sql: """
            UPDATE workspace_terminal_session_ownership
            SET cleanup_state = 'pending', cleanup_requested_at = ?
            WHERE cleanup_state = 'owned'
                AND session_id IN (
                    SELECT member.session_id FROM workspace_undo_close_member AS member
                    JOIN workspace_undo_close AS operation ON operation.close_id = member.close_id
                    WHERE operation.workspace_id = ? AND operation.state IN ('evicted', 'expired', 'restored')
                )
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
        arguments: [requestedAt.timeIntervalSince1970, workspaceID.uuidString]
    )
}
