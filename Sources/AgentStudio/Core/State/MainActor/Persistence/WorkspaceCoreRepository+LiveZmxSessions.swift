import AgentStudioInfrastructure
import Foundation
import GRDB

extension WorkspaceCoreRepository {
    /// Restore R3 "gather" cost phase (SR12-adjacent telemetry): the GRDB
    /// read below is the real synchronous membership lookup the restore path
    /// pays for, so it is what gets timed — never the actor hops around it.
    func liveZmxSessionsByPane(
        workspaceId: UUID, performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil
    ) async throws -> [UUID: ZmxSessionID] {
        try await databaseWriter.read { database in
            let gatherStart = ContinuousClock.now
            let executedOnMainThread = Thread.isMainThread
            defer {
                performanceTraceRecorder?.recordRestorePhaseDuration(
                    .restoreForegroundGather, duration: gatherStart.duration(to: .now),
                    executedOnMainThread: executedOnMainThread)
            }
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT pane.id, terminal.zmx_session_id
                    FROM pane_content_terminal AS terminal JOIN pane ON pane.id = terminal.pane_id
                    WHERE pane.workspace_id = ? AND terminal.provider = 'zmx'
                    """, arguments: [workspaceId.uuidString])
            return try Dictionary(
                uniqueKeysWithValues: rows.map { row in
                    let rawPane: String = row["id"]
                    let rawSession: String = row["zmx_session_id"]
                    guard let paneId = UUID(uuidString: rawPane), let sessionId = ZmxSessionID(restoring: rawSession)
                    else {
                        throw WorkspaceUndoJournalFailure.invalidStoredIdentifier
                    }
                    return (paneId, sessionId)
                })
        }
    }
}
