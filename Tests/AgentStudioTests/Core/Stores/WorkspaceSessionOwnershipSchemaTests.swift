import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore

@Suite("Workspace session ownership schema")
struct WorkspaceSessionOwnershipSchemaTests {
    @Test("ordinary schema setup registers existing opaque sessions without changing panes")
    func schemaSetupPreservesExistingSessions() throws {
        let database = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceCoreMigrations.migrator.migrate(database, upTo: "016_add_pane_association_facets")
        let fixture = WorkspaceCoreTopologyRepositoryFixture(
            repository: WorkspaceCoreRepository(databaseWriter: database),
            databaseQueue: database
        )
        let workspaceID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        try fixture.repository.upsertWorkspace(
            .init(id: workspaceID, name: "Existing", createdAt: .distantPast, updatedAt: .distantPast)
        )
        try fixture.insertPane(workspaceId: workspaceID, paneId: paneID, cwd: URL(filePath: "/tmp/journal-existing"))
        let original = try fixture.repository.fetchPaneGraph(workspaceId: workspaceID)

        try WorkspaceCoreMigrations.migrate(database)

        #expect(try fixture.repository.fetchPaneGraph(workspaceId: workspaceID) == original)
        let registered = try database.read { database in
            try String.fetchOne(database, sql: "SELECT session_id FROM workspace_terminal_session_ownership")
        }
        #expect(registered == "test-\(paneID.uuidString)")
    }

    @Test("close deadline and undo membership survive database reopen")
    func undoMembershipSurvivesDatabaseReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUIDv7.generate().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databasePath = directory.appendingPathComponent("core.sqlite").path
        let closeID = UUIDv7.generate().uuidString
        let workspaceID = UUIDv7.generate().uuidString
        let paneID = UUIDv7.generate().uuidString
        let sessionID = ZmxSessionID.generateUUIDv7().rawValue
        let database = try DatabaseQueue(path: databasePath)
        try WorkspaceCoreMigrations.migrate(database)
        try database.write { database in
            try database.execute(
                sql: "INSERT INTO workspace_terminal_session_ownership(session_id) VALUES (?)",
                arguments: [sessionID]
            )
            try database.execute(
                sql: """
                    INSERT INTO workspace_undo_close(
                        close_id, workspace_id, close_sequence, close_kind, closed_at, expires_at,
                        state, snapshot_version, snapshot_payload, deadline_boot_id, deadline_uptime_ns
                    ) VALUES (?, ?, 1, 'pane', 100, 400, 'available', 1, ?, 'same-boot', 400000000000)
                    """,
                arguments: [closeID, workspaceID, Data("{}".utf8)]
            )
            try database.execute(
                sql: "INSERT INTO workspace_undo_close_member VALUES (?, ?, ?)",
                arguments: [closeID, paneID, sessionID]
            )
        }
        try database.close()

        let reopened = try DatabaseQueue(path: databasePath)
        defer { try? reopened.close() }
        try reopened.read { database in
            let storedRow = try Row.fetchOne(database, sql: "SELECT * FROM workspace_undo_close")
            let row = try #require(storedRow)
            #expect(row["close_id"] as String == closeID)
            #expect(row["expires_at"] as Double == 400)
            #expect(row["deadline_uptime_ns"] as Int64 == 400_000_000_000)
            #expect(row["state"] as String == "available")
            #expect(
                try String.fetchOne(database, sql: "SELECT session_id FROM workspace_undo_close_member") == sessionID
            )
        }
    }

    @Test("available undo ownership survives live pane deletion and rejects pruning")
    func availableUndoSurvivesPaneDeletion() throws {
        // Arrange: the fixture uses the production core schema setup.
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let workspaceID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let closeID = UUIDv7.generate()
        let sessionID = "test-\(paneID.uuidString)"
        try fixture.repository.upsertWorkspace(
            .init(
                id: workspaceID,
                name: "Undo ownership",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try fixture.insertPane(
            workspaceId: workspaceID,
            paneId: paneID,
            cwd: URL(filePath: "/tmp/session-ownership-schema")
        )

        // Act: model the storage portion of one close transaction.
        try fixture.databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO workspace_terminal_session_ownership(session_id, cleanup_state)
                    VALUES (?, 'owned')
                    """,
                arguments: [sessionID]
            )
            try database.execute(
                sql: """
                    INSERT INTO workspace_undo_close(
                        close_id, workspace_id, close_sequence, close_kind,
                        closed_at, expires_at, state, snapshot_version, snapshot_payload,
                        deadline_boot_id, deadline_uptime_ns
                    ) VALUES (?, ?, 1, 'pane', 100, 400, 'available', 1, ?, 'boot-fixture', 300000000000)
                    """,
                arguments: [closeID.uuidString, workspaceID.uuidString, Data("{}".utf8)]
            )
            try database.execute(
                sql: """
                    INSERT INTO workspace_undo_close_member(close_id, pane_id, session_id)
                    VALUES (?, ?, ?)
                    """,
                arguments: [closeID.uuidString, paneID.uuidString, sessionID]
            )
            try database.execute(sql: "DELETE FROM pane WHERE id = ?", arguments: [paneID.uuidString])
        }

        // Assert: historical members do not cascade with the live pane row.
        let retainedSession = try fixture.databaseQueue.read { database in
            try String.fetchOne(
                database,
                sql: "SELECT session_id FROM workspace_undo_close_member WHERE close_id = ?",
                arguments: [closeID.uuidString]
            )
        }
        #expect(retainedSession == sessionID)
        #expect(throws: DatabaseError.self) {
            try fixture.databaseQueue.write { database in
                try database.execute(
                    sql: """
                        UPDATE workspace_terminal_session_ownership
                        SET cleanup_state = 'pending', cleanup_requested_at = 400
                        WHERE session_id = ?
                        """,
                    arguments: [sessionID]
                )
            }
        }
        #expect(throws: DatabaseError.self) {
            try fixture.databaseQueue.write { database in
                try database.execute(
                    sql: "DELETE FROM workspace_undo_close_member WHERE close_id = ?",
                    arguments: [closeID.uuidString]
                )
            }
        }
        #expect(throws: DatabaseError.self) {
            try fixture.databaseQueue.write { database in
                try database.execute(
                    sql: "DELETE FROM workspace_undo_close WHERE close_id = ?",
                    arguments: [closeID.uuidString]
                )
            }
        }
    }
}
