import AgentStudioInfrastructure
import Foundation
import GRDB

extension WorkspaceCoreRepository {
    func fetchAvailableUndoCloses(workspaceID: UUID) throws -> [WorkspaceUndoCloseRecord] {
        try databaseWriter.read { database in
            try Row.fetchAll(
                database,
                sql: """
                    SELECT * FROM workspace_undo_close
                    WHERE workspace_id = ? AND state = 'available' ORDER BY close_sequence DESC
                    """,
                arguments: [workspaceID.uuidString]
            ).map { try decodeUndoClose($0, database: database) }
        }
    }

    func recoverUndoCloseDeadlines(workspaceID: UUID, time: WorkspaceUndoJournalTime) throws {
        try validateUndoJournalTime(time)
        guard let grace = Int64(exactly: AppPolicies.WorkspacePersistence.undoGracePeriod.nanosecondsForTaskSleep)
        else {
            throw WorkspaceUndoJournalFailure.deadlineOverflow
        }
        let (deadline, overflow) = time.uptimeNanoseconds.addingReportingOverflow(grace)
        guard !overflow else { throw WorkspaceUndoJournalFailure.deadlineOverflow }
        try databaseWriter.write { database in
            try database.execute(
                sql: """
                    UPDATE workspace_undo_close SET deadline_boot_id = ?, deadline_uptime_ns = ?
                    WHERE workspace_id = ? AND state = 'available' AND deadline_boot_id <> ?
                    """,
                arguments: [time.bootID, deadline, workspaceID.uuidString, time.bootID]
            )
        }
    }

    func expireUndoCloses(
        workspaceID: UUID,
        time: WorkspaceUndoJournalTime
    ) throws -> [WorkspaceUndoCloseRetirement] {
        try validateUndoJournalTime(time)
        return try databaseWriter.write { database in
            let closeIDs = try String.fetchAll(
                database,
                sql: """
                    SELECT close_id FROM workspace_undo_close
                    WHERE workspace_id = ? AND state = 'available'
                        AND deadline_boot_id = ? AND deadline_uptime_ns <= ?
                    ORDER BY close_sequence
                    """,
                arguments: [workspaceID.uuidString, time.bootID, time.uptimeNanoseconds]
            )
            for rawID in closeIDs {
                try database.execute(
                    sql: "UPDATE workspace_undo_close SET state = 'expired' WHERE close_id = ?",
                    arguments: [rawID]
                )
            }
            let retired = try closeIDs.map { try readUndoCloseRetirement(rawCloseID: $0, database: database) }
            try markFinishedUndoSessionsForCleanup(database, workspaceID: workspaceID, requestedAt: time.utc)
            try pruneFinishedUndoRows(workspaceID: workspaceID, database: database)
            return retired
        }
    }
}

func validateUndoJournalTime(_ time: WorkspaceUndoJournalTime) throws {
    guard !time.bootID.isEmpty, time.uptimeNanoseconds >= 0, time.utc.timeIntervalSince1970.isFinite else {
        throw WorkspaceUndoJournalFailure.invalidClock
    }
}

func decodeUndoClose(_ row: Row, database: Database) throws -> WorkspaceUndoCloseRecord {
    let rawCloseID: String = row["close_id"]
    let rawWorkspaceID: String = row["workspace_id"]
    guard let closeID = UUID(uuidString: rawCloseID), let workspaceID = UUID(uuidString: rawWorkspaceID) else {
        throw WorkspaceUndoJournalFailure.invalidStoredIdentifier
    }
    let version: Int = row["snapshot_version"]
    let payload: Data = row["snapshot_payload"]
    let kind: String = row["close_kind"]
    let members = try readUndoCloseMembers(closeID: closeID, database: database)
    let snapshot = try decodeValidatedUndoCloseSnapshot(
        version: version, payload: payload, kind: kind, members: members)
    return .init(
        closeID: closeID,
        workspaceID: workspaceID,
        sequence: row["close_sequence"],
        closedAt: Date(timeIntervalSince1970: row["closed_at"]),
        expiresAt: Date(timeIntervalSince1970: row["expires_at"]),
        deadlineBootID: row["deadline_boot_id"],
        deadlineUptimeNanoseconds: row["deadline_uptime_ns"],
        snapshot: snapshot
    )
}

func readUndoCloseMembers(closeID: UUID, database: Database) throws -> [WorkspaceUndoCloseWrite.Member] {
    try Row.fetchAll(
        database,
        sql: "SELECT pane_id, session_id FROM workspace_undo_close_member WHERE close_id = ? ORDER BY pane_id",
        arguments: [closeID.uuidString]
    ).map { row in
        let rawPaneID: String = row["pane_id"]
        guard let paneID = UUID(uuidString: rawPaneID) else {
            throw WorkspaceUndoJournalFailure.invalidStoredIdentifier
        }
        let rawSessionID: String? = row["session_id"]
        let sessionID: ZmxSessionID?
        if let rawSessionID {
            guard let restoredID = ZmxSessionID(restoring: rawSessionID) else {
                throw WorkspaceUndoJournalFailure.invalidStoredIdentifier
            }
            sessionID = restoredID
        } else {
            sessionID = nil
        }
        return .init(paneID: paneID, sessionID: sessionID)
    }
}
