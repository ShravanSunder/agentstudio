import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore

@Suite("Workspace durable undo recovery")
struct WorkspaceUndoCloseRecoveryTests {
    @Test("recovery keeps the chosen deadline across ordinary relaunch and expires at the boundary")
    func recoveryDoesNotRenewGrace() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let workspaceID = UUIDv7.generate()
        let closeID = UUIDv7.generate()
        let pane = makePane(id: UUIDv7.generate())
        let payload = WorkspaceUndoCloseSnapshot.tab(
            tab: Tab(paneId: pane.id), panes: [pane], tabIndex: 0
        )
        try writeFixtureClose(fixture, workspaceID: workspaceID, closeID: closeID, payload: payload)

        try fixture.repository.recoverUndoCloseDeadlines(
            workspaceID: workspaceID,
            time: .init(utc: Date(timeIntervalSince1970: 500), bootID: "new-boot", uptimeNanoseconds: 50_000_000_000)
        )
        let recovered = try fixture.repository.fetchAvailableUndoCloses(workspaceID: workspaceID)
        #expect(recovered.count == 1)
        #expect(recovered.first?.snapshot == payload)
        #expect(recovered.first?.deadlineUptimeNanoseconds == 350_000_000_000)

        try fixture.repository.recoverUndoCloseDeadlines(
            workspaceID: workspaceID,
            time: .init(utc: Date(timeIntervalSince1970: 100), bootID: "new-boot", uptimeNanoseconds: 100_000_000_000)
        )
        let reloaded = try fixture.repository.fetchAvailableUndoCloses(workspaceID: workspaceID)
        #expect(reloaded.first?.deadlineUptimeNanoseconds == 350_000_000_000)
        let beforeDeadline = try fixture.repository.expireUndoCloses(
            workspaceID: workspaceID,
            time: .init(utc: Date(timeIntervalSince1970: 900), bootID: "new-boot", uptimeNanoseconds: 349_999_999_999)
        )
        #expect(beforeDeadline.isEmpty)
        let atDeadline = try fixture.repository.expireUndoCloses(
            workspaceID: workspaceID,
            time: .init(utc: Date(timeIntervalSince1970: 900), bootID: "new-boot", uptimeNanoseconds: 350_000_000_000)
        )
        #expect(atDeadline.map(\.closeID) == [closeID])
        #expect(try fixture.repository.fetchAvailableUndoCloses(workspaceID: workspaceID).isEmpty)
        let cleanup = try fixture.databaseQueue.read { database in
            try String.fetchOne(database, sql: "SELECT cleanup_state FROM workspace_terminal_session_ownership")
        }
        #expect(cleanup == "pending")
    }

    @Test("corrupt undo payload is rejected without consuming its ownership")
    func corruptPayloadDoesNotLoseOwnership() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let workspaceID = UUIDv7.generate()
        let closeID = UUIDv7.generate()
        let pane = makePane(id: UUIDv7.generate())
        let payload = WorkspaceUndoCloseSnapshot.tab(tab: Tab(paneId: pane.id), panes: [pane], tabIndex: 0)
        try writeFixtureClose(fixture, workspaceID: workspaceID, closeID: closeID, payload: payload)
        try fixture.databaseQueue.write { database in
            try database.execute(
                sql: "UPDATE workspace_undo_close SET snapshot_payload = ? WHERE close_id = ?",
                arguments: [Data("invalid".utf8), closeID.uuidString]
            )
        }

        #expect(throws: (any Error).self) {
            try fixture.repository.fetchAvailableUndoCloses(workspaceID: workspaceID)
        }
        let state = try fixture.databaseQueue.read { database in
            try String.fetchOne(database, sql: "SELECT state FROM workspace_undo_close")
        }
        #expect(state == "available")
    }

    private func writeFixtureClose(
        _ fixture: WorkspaceCoreTopologyRepositoryFixture,
        workspaceID: UUID,
        closeID: UUID,
        payload: WorkspaceUndoCloseSnapshot
    ) throws {
        try fixture.repository.replaceWorkspaceSnapshot(
            workspace: .init(
                id: workspaceID, name: "Recovery", createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            paneGraph: .init(panes: []),
            tabShells: [],
            tabGraph: .init(tabs: []),
            undoChange: .record(
                .init(
                    closeID: closeID, workspaceID: workspaceID, kind: payload.kind,
                    closedAt: Date(timeIntervalSince1970: 100), expiresAt: Date(timeIntervalSince1970: 400),
                    deadlineBootID: "old-boot", deadlineUptimeNanoseconds: 400_000_000_000,
                    snapshotVersion: 1, snapshotPayload: try JSONEncoder().encode(payload), members: payload.members
                ))
        )
    }
}
