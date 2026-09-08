import Foundation
import GRDB
import Testing

@testable import AgentStudioCore

@Suite("Workspace terminal cleanup persistence")
struct WorkspaceTerminalCleanupPersistenceTests {
    @Test("first identity is immutable and survives repository recreation")
    func firstIdentityIsImmutable() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let sessionID = ZmxSessionID.generateUUIDv7()
        let firstIdentity = Data("original-incarnation".utf8)
        let replacementIdentity = Data("replacement-incarnation".utf8)
        try fixture.databaseQueue.write { database in
            try database.execute(
                sql: "INSERT INTO workspace_terminal_session_ownership(session_id) VALUES (?)",
                arguments: [sessionID.rawValue])
        }

        #expect(try fixture.repository.recordTerminalSessionIdentity(sessionID: sessionID, identity: firstIdentity))
        #expect(try fixture.repository.recordTerminalSessionIdentity(sessionID: sessionID, identity: firstIdentity))
        let reopenedRepository = WorkspaceCoreRepository(databaseWriter: fixture.databaseQueue)
        #expect(
            try !reopenedRepository.recordTerminalSessionIdentity(sessionID: sessionID, identity: replacementIdentity))
        let stored = try fixture.databaseQueue.read { database in
            try Data.fetchOne(database, sql: "SELECT process_identity FROM workspace_terminal_session_ownership")
        }
        #expect(stored == firstIdentity)
    }

    @Test("completion requires pending state and the recorded incarnation")
    func completionRequiresPendingRecordedIdentity() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let sessionID = ZmxSessionID.generateUUIDv7()
        let identity = Data("original-incarnation".utf8)
        let completedAt = Date(timeIntervalSince1970: 500)
        try fixture.databaseQueue.write { database in
            try database.execute(
                sql: "INSERT INTO workspace_terminal_session_ownership(session_id, process_identity) VALUES (?, ?)",
                arguments: [sessionID.rawValue, identity])
        }
        #expect(
            try !fixture.repository.completeTerminalSessionCleanup(
                sessionID: sessionID, expectedIdentity: identity, completedAt: completedAt))
        try fixture.databaseQueue.write { database in
            try database.execute(
                sql: """
                    UPDATE workspace_terminal_session_ownership
                    SET cleanup_state = 'pending', cleanup_requested_at = 400, last_cleanup_error = 'timeout'
                    WHERE session_id = ?
                    """, arguments: [sessionID.rawValue])
        }
        #expect(
            try !fixture.repository.completeTerminalSessionCleanup(
                sessionID: sessionID, expectedIdentity: Data("replacement".utf8), completedAt: completedAt))
        #expect(
            try !fixture.repository.completeTerminalSessionCleanup(
                sessionID: sessionID, expectedIdentity: nil, completedAt: completedAt))
        #expect(
            try fixture.repository.completeTerminalSessionCleanup(
                sessionID: sessionID, expectedIdentity: identity, completedAt: completedAt))
        try fixture.databaseQueue.read { database in
            let row = try #require(
                try Row.fetchOne(database, sql: "SELECT * FROM workspace_terminal_session_ownership"))
            #expect(row["cleanup_state"] as String == "completed")
            #expect(row["cleanup_completed_at"] as Double? == 500)
            #expect(row["last_cleanup_error"] as String? == nil)
        }
    }

    @Test("a correlated pending session can record its first process observation")
    func knownPendingSessionRecordsFirstObservation() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let sessionID = ZmxSessionID.generateUUIDv7()
        let identity = Data("observed-after-close".utf8)
        try fixture.databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO workspace_terminal_session_ownership(session_id, cleanup_state, cleanup_requested_at)
                    VALUES (?, 'pending', 400)
                    """, arguments: [sessionID.rawValue])
        }
        #expect(try fixture.repository.recordTerminalSessionIdentity(sessionID: sessionID, identity: identity))
        #expect(
            try !fixture.repository.recordTerminalSessionIdentity(
                sessionID: sessionID, identity: Data("replacement-incarnation".utf8)))
        #expect(
            try fixture.repository.completeTerminalSessionCleanup(
                sessionID: sessionID, expectedIdentity: identity, completedAt: Date(timeIntervalSince1970: 500)))
        #expect(try fixture.repository.pendingTerminalSessionIDs().isEmpty)
    }

    @Test("an unrecorded session cannot gain cleanup authority through observation")
    func unrecordedSessionCannotBeAdopted() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let sessionID = ZmxSessionID.generateUUIDv7()
        let identity = Data("unknown-session".utf8)
        #expect(try !fixture.repository.recordTerminalSessionIdentity(sessionID: sessionID, identity: identity))
        #expect(
            try !fixture.repository.completeTerminalSessionCleanup(
                sessionID: sessionID, expectedIdentity: identity, completedAt: Date(timeIntervalSince1970: 500)))
        #expect(try fixture.repository.terminalSessionCleanupBatch(after: nil).isEmpty)
        #expect(
            try !fixture.repository.completeTerminalSessionCleanup(
                sessionID: sessionID, expectedIdentity: nil, completedAt: Date(timeIntervalSince1970: 500)))
    }
}
