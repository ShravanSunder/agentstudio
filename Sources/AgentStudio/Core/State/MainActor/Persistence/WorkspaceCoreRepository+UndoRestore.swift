import Foundation
import GRDB

func restoreUndoClose(
    closeID: UUID,
    workspaceID: UUID,
    time: WorkspaceUndoJournalTime,
    paneGraph: WorkspaceCoreRepository.PaneGraphRecord,
    database: Database
) throws {
    try validateUndoJournalTime(time)
    guard
        let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM workspace_undo_close WHERE close_id = ? AND workspace_id = ? AND state = 'available'",
            arguments: [closeID.uuidString, workspaceID.uuidString]
        )
    else {
        throw WorkspaceUndoJournalFailure.undoUnavailable
    }
    let close = try decodeUndoClose(row, database: database)
    guard close.deadlineBootID == time.bootID else { throw WorkspaceUndoJournalFailure.deadlineNeedsRecovery }
    guard time.uptimeNanoseconds < close.deadlineUptimeNanoseconds else {
        throw WorkspaceUndoJournalFailure.undoExpired
    }
    let restoredMembers = Set(
        paneGraph.panes.map { pane -> WorkspaceUndoCloseWrite.Member in
            let sessionID: ZmxSessionID?
            if case .terminal(_, _, let identity) = pane.content {
                sessionID = identity
            } else {
                sessionID = nil
            }
            return .init(paneID: pane.id, sessionID: sessionID)
        }
    )
    guard close.snapshot.members.allSatisfy(restoredMembers.contains) else {
        throw WorkspaceUndoJournalFailure.restoreMembershipMismatch
    }
    try database.execute(
        sql: "UPDATE workspace_undo_close SET state = 'restored' WHERE close_id = ?",
        arguments: [closeID.uuidString]
    )
}
