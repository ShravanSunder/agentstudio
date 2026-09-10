import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("Workspace terminal ownership admission", .serialized)
struct WorkspaceTerminalOwnershipAdmissionTests {
    @Test("live terminal persistence registers ownership and rejects reattachment after retirement")
    func liveTerminalRegistrationAndRetirementAdmission() async throws {
        let workspaceID = UUIDv7.generate()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let datastore = try await preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        let pane = makePane(id: UUIDv7.generate())
        let sessionID = try #require(pane.terminalState?.zmxSessionID)
        let bundle = WorkspaceSQLiteSaveBundle(
            workspace: .init(id: workspaceID, panes: [pane], tabs: [Tab(paneId: pane.id)])
        )
        try await datastore.saveWorkspaceSnapshotBundle(bundle)
        let registered = try await fixture.coreRepository.databaseWriter.read { database in
            try String.fetchOne(
                database,
                sql: "SELECT cleanup_state FROM workspace_terminal_session_ownership WHERE session_id = ?",
                arguments: [sessionID.rawValue])
        }
        #expect(registered == "owned")

        try await datastore.saveWorkspaceSnapshotBundle(.init(workspace: .init(id: workspaceID)))
        try await fixture.coreRepository.databaseWriter.write { database in
            try database.execute(
                sql: "INSERT INTO workspace_terminal_session_ownership(session_id) VALUES (?) ON CONFLICT DO NOTHING",
                arguments: [sessionID.rawValue])
            try database.execute(
                sql:
                    "UPDATE workspace_terminal_session_ownership SET cleanup_state = 'pending', cleanup_requested_at = 400 WHERE session_id = ?",
                arguments: [sessionID.rawValue])
        }
        await #expect(throws: DatabaseError.self) {
            try await datastore.saveWorkspaceSnapshotBundle(bundle)
        }
        #expect(try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceID).panes.isEmpty)
    }

    @Test("terminal identity cannot be reassigned to an unregistered session through SQL")
    func terminalForeignKeyRejectsUnknownSession() async throws {
        let workspaceID = UUIDv7.generate()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let datastore = try await preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        let pane = makePane(id: UUIDv7.generate())
        try await datastore.saveWorkspaceSnapshotBundle(
            .init(workspace: .init(id: workspaceID, panes: [pane], tabs: [Tab(paneId: pane.id)]))
        )
        let unknownID = ZmxSessionID.generateUUIDv7()
        await #expect(throws: DatabaseError.self) {
            try await fixture.coreRepository.databaseWriter.write { database in
                try database.execute(
                    sql: "UPDATE pane_content_terminal SET zmx_session_id = ? WHERE pane_id = ?",
                    arguments: [unknownID.rawValue, pane.id.uuidString])
            }
        }
    }
}
