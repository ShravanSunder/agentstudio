import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore

@Suite("Workspace undo history pruning")
struct WorkspaceUndoHistoryPruningTests {
    @Test("bounded pruning preserves available undo and unfinished session cleanup")
    func pruningPreservesUnfinishedOwnership() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let workspaceID = UUIDv7.generate()
        let pendingCloseID = UUIDv7.generate()
        let availableCloseID = UUIDv7.generate()
        let sessionID = ZmxSessionID.generateUUIDv7()
        try fixture.databaseQueue.write { database in
            try database.execute(
                sql: "INSERT INTO workspace_terminal_session_ownership(session_id) VALUES (?)",
                arguments: [sessionID.rawValue])
            try insertClose(pendingCloseID, sequence: 1, workspaceID: workspaceID, available: true, database: database)
            try database.execute(
                sql: "INSERT INTO workspace_undo_close_member VALUES (?, ?, ?)",
                arguments: [pendingCloseID.uuidString, UUIDv7.generate().uuidString, sessionID.rawValue])
            try database.execute(
                sql: "UPDATE workspace_undo_close SET state = 'expired' WHERE close_id = ?",
                arguments: [pendingCloseID.uuidString])
            try database.execute(
                sql:
                    "UPDATE workspace_terminal_session_ownership SET cleanup_state = 'pending', cleanup_requested_at = 400 WHERE session_id = ?",
                arguments: [sessionID.rawValue])
            for sequence in 2...203 {
                try insertClose(
                    UUIDv7.generate(), sequence: sequence, workspaceID: workspaceID, available: false,
                    database: database)
            }
            try insertClose(
                availableCloseID, sequence: 204, workspaceID: workspaceID, available: true, database: database)
        }

        #expect(try fixture.repository.pruneCompletedUndoHistory(workspaceID: workspaceID) == 100)
        #expect(try fixture.repository.pruneCompletedUndoHistory(workspaceID: workspaceID) == 2)
        #expect(try fixture.repository.pruneCompletedUndoHistory(workspaceID: workspaceID) == 0)

        try fixture.databaseQueue.read { database in
            let count = try Int.fetchOne(database, sql: "SELECT count(*) FROM workspace_undo_close")
            #expect(count == 102)
            #expect(
                try String.fetchOne(
                    database, sql: "SELECT state FROM workspace_undo_close WHERE close_id = ?",
                    arguments: [availableCloseID.uuidString]) == "available")
            #expect(
                try String.fetchOne(
                    database, sql: "SELECT session_id FROM workspace_undo_close_member WHERE close_id = ?",
                    arguments: [pendingCloseID.uuidString]) == sessionID.rawValue)
            #expect(
                try String.fetchOne(
                    database,
                    sql: "SELECT cleanup_state FROM workspace_terminal_session_ownership WHERE session_id = ?",
                    arguments: [sessionID.rawValue]) == "pending")
        }
    }

    private func insertClose(_ closeID: UUID, sequence: Int, workspaceID: UUID, available: Bool, database: Database)
        throws
    {
        try database.execute(
            sql: """
                INSERT INTO workspace_undo_close(
                    close_id, workspace_id, close_sequence, close_kind, closed_at, expires_at,
                    state, snapshot_version, snapshot_payload, deadline_boot_id, deadline_uptime_ns
                ) VALUES (?, ?, ?, 'pane', 100, 400, ?, 1, ?, 'boot-fixture', 400000000000)
                """,
            arguments: [
                closeID.uuidString, workspaceID.uuidString, sequence,
                available ? "available" : "expired", available ? Data("{}".utf8) : nil,
            ])
    }
}
