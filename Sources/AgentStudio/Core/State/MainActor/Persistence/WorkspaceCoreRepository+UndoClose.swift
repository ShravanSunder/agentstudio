import AgentStudioInfrastructure
import Foundation
import GRDB

/// Executes inside the same transaction as the workspace composition replacement.
func writeUndoClose(_ close: WorkspaceUndoCloseWrite, in database: Database) throws -> WorkspaceUndoJournalReceipt {
    _ = try decodeValidatedUndoCloseSnapshot(
        version: close.snapshotVersion, payload: close.snapshotPayload,
        kind: close.kind.rawValue, members: close.members
    )
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

    let evictedIDs = try String.fetchAll(
        database,
        sql: """
            SELECT close_id FROM (
                SELECT close_id, close_sequence FROM workspace_undo_close
                WHERE workspace_id = ? AND state = 'available'
                ORDER BY close_sequence DESC LIMIT -1 OFFSET ?
            ) ORDER BY close_sequence
            """,
        arguments: [close.workspaceID.uuidString, AppPolicies.WorkspacePersistence.maximumAvailableUndoCloses]
    )
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
    let retiredCloses = try evictedIDs.map { try readUndoCloseRetirement(rawCloseID: $0, database: database) }
    try markFinishedUndoSessionsForCleanup(
        database,
        workspaceID: close.workspaceID,
        requestedAt: close.closedAt
    )
    try pruneFinishedUndoRows(workspaceID: close.workspaceID, database: database)
    return try readUndoJournalReceipt(workspaceID: close.workspaceID, retiredCloses: retiredCloses, database: database)
}

func readUndoJournalReceipt(
    workspaceID: UUID,
    retiredCloses: [WorkspaceUndoCloseRetirement],
    database: Database
) throws -> WorkspaceUndoJournalReceipt {
    let available = try String.fetchAll(
        database,
        sql:
            "SELECT close_id FROM workspace_undo_close WHERE workspace_id = ? AND state = 'available' ORDER BY close_sequence DESC",
        arguments: [workspaceID.uuidString]
    ).map { rawID -> UUID in
        guard let closeID = UUID(uuidString: rawID) else { throw WorkspaceUndoJournalFailure.invalidStoredIdentifier }
        return closeID
    }
    return .init(availableCloseIDs: available, retiredCloses: retiredCloses)
}

func markFinishedUndoSessionsForCleanup(
    _ database: Database,
    workspaceID: UUID,
    requestedAt: Date
) throws {
    try markUnownedTerminalSessionsForCleanup(database, finishedUndoWorkspaceID: workspaceID, requestedAt: requestedAt)
}
