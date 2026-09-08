import AgentStudioInfrastructure
import Foundation
import GRDB

extension WorkspaceCoreRepository {
    /// One existing-size batch per pass; another pass is requested only when rows were removed.
    func pruneCompletedHistoryBatch() throws -> Bool {
        try databaseWriter.write { database in
            let rawWorkspaceID = try String.fetchOne(
                database,
                sql: """
                    SELECT operation.workspace_id FROM workspace_undo_close AS operation
                    WHERE operation.state <> 'available'
                        AND NOT EXISTS (
                            SELECT 1 FROM workspace_undo_close_member AS member
                            JOIN workspace_terminal_session_ownership AS session USING(session_id)
                            WHERE member.close_id = operation.close_id AND session.cleanup_state = 'pending'
                        )
                    GROUP BY operation.workspace_id HAVING count(*) > ?
                    ORDER BY operation.workspace_id LIMIT 1
                    """, arguments: [AppPolicies.WorkspacePersistence.completedUndoHistoryLimit])
            if let rawWorkspaceID {
                guard let workspaceID = UUID(uuidString: rawWorkspaceID) else {
                    throw WorkspaceUndoJournalFailure.invalidStoredIdentifier
                }
                return try pruneFinishedUndoRows(workspaceID: workspaceID, database: database) > 0
            }
            return try pruneUnreferencedCompletedSessions(database: database) > 0
        }
    }

    @discardableResult
    func pruneCompletedUndoHistory(workspaceID: UUID) throws -> Int {
        try databaseWriter.write { database in
            try pruneFinishedUndoRows(workspaceID: workspaceID, database: database)
        }
    }
}

/// Available undo and pending cleanup are excluded before applying the diagnostic-history cap.
@discardableResult
func pruneFinishedUndoRows(workspaceID: UUID, database: Database) throws -> Int {
    let closeIDs = try String.fetchAll(
        database,
        sql: """
            SELECT close_id FROM (
                SELECT operation.close_id, operation.close_sequence FROM workspace_undo_close AS operation
                WHERE operation.workspace_id = ? AND operation.state <> 'available'
                    AND NOT EXISTS (
                        SELECT 1 FROM workspace_undo_close_member AS member
                        JOIN workspace_terminal_session_ownership AS session USING(session_id)
                        WHERE member.close_id = operation.close_id AND session.cleanup_state = 'pending'
                    )
                ORDER BY operation.close_sequence DESC LIMIT -1 OFFSET ?
            ) ORDER BY close_sequence LIMIT ?
            """,
        arguments: [
            workspaceID.uuidString, AppPolicies.WorkspacePersistence.completedUndoHistoryLimit,
            AppPolicies.WorkspacePersistence.completedUndoPruneBatchSize,
        ])
    for closeID in closeIDs {
        try database.execute(sql: "DELETE FROM workspace_undo_close_member WHERE close_id = ?", arguments: [closeID])
        try database.execute(sql: "DELETE FROM workspace_undo_close WHERE close_id = ?", arguments: [closeID])
    }
    _ = try pruneUnreferencedCompletedSessions(database: database)
    return closeIDs.count
}

private func pruneUnreferencedCompletedSessions(database: Database) throws -> Int {
    try database.execute(
        sql: """
            DELETE FROM workspace_terminal_session_ownership WHERE session_id IN (
                SELECT session.session_id FROM workspace_terminal_session_ownership AS session
                WHERE session.cleanup_state = 'completed'
                    AND NOT EXISTS (SELECT 1 FROM pane_content_terminal WHERE zmx_session_id = session.session_id)
                    AND NOT EXISTS (SELECT 1 FROM workspace_undo_close_member WHERE session_id = session.session_id)
                ORDER BY session.cleanup_completed_at, session.session_id LIMIT ?
            )
            """, arguments: [AppPolicies.WorkspacePersistence.completedUndoPruneBatchSize])
    return try Int.fetchOne(database, sql: "SELECT changes()") ?? 0
}
