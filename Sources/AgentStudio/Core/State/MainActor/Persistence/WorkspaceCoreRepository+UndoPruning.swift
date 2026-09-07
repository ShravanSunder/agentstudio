import AgentStudioInfrastructure
import Foundation
import GRDB

extension WorkspaceCoreRepository {
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
    return closeIDs.count
}
