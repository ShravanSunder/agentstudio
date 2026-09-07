import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("Workspace undo startup recovery", .serialized)
struct WorkspaceUndoStartupRecoveryTests {
    @Test("startup admits only known unowned sessions for cleanup and preserves uncertainty")
    func startupReconcilesOnlyKnownUnownedSessions() async throws {
        let workspaceID = UUIDv7.generate()
        let otherWorkspaceID = UUIDv7.generate()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let datastore = try await preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        let ownedPane = makePane(id: UUIDv7.generate())
        let ownedSessionID = try #require(ownedPane.terminalState?.zmxSessionID)
        try await datastore.saveWorkspaceSnapshotBundle(
            .init(workspace: .init(id: otherWorkspaceID, panes: [ownedPane], tabs: [Tab(paneId: ownedPane.id)]))
        )
        let orphanID = ZmxSessionID.generateUUIDv7()
        let alreadyPendingID = ZmxSessionID.generateUUIDv7()
        try await fixture.coreRepository.databaseWriter.write { database in
            try database.execute(
                sql: "INSERT INTO workspace_terminal_session_ownership(session_id) VALUES (?)",
                arguments: [orphanID.rawValue])
            try database.execute(
                sql: """
                    INSERT INTO workspace_terminal_session_ownership(session_id, cleanup_state, cleanup_requested_at)
                    VALUES (?, 'pending', 100)
                    """, arguments: [alreadyPendingID.rawValue])
        }

        let uncertain = try await datastore.recoverUndoJournal(workspaceID: workspaceID, time: nil)
        #expect(uncertain.pendingSessionIDs == [alreadyPendingID])
        let recovered = try await datastore.recoverUndoJournal(
            workspaceID: workspaceID,
            time: .init(
                utc: Date(timeIntervalSince1970: 200), bootID: "boot-fixture", uptimeNanoseconds: 200_000_000_000)
        )
        #expect(recovered.pendingSessionIDs == [orphanID, alreadyPendingID])
        let liveState = try await fixture.coreRepository.databaseWriter.read { database in
            try String.fetchOne(
                database, sql: "SELECT cleanup_state FROM workspace_terminal_session_ownership WHERE session_id = ?",
                arguments: [ownedSessionID.rawValue])
        }
        #expect(liveState == "owned")
    }

    @Test("startup recovers deadlines across workspaces and ordinary relaunch cannot renew them")
    func startupRecoversAllWorkspaceDeadlinesOnce() async throws {
        let workspaceIDs = [UUIDv7.generate(), UUIDv7.generate()]
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceIDs[0])
        let datastore = try await preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        for workspaceID in workspaceIDs {
            let pane = makePane(id: UUIDv7.generate())
            let tab = Tab(paneId: pane.id)
            let close = try WorkspaceUndoComposition.prepareClose(
                in: .init(workspace: .init(id: workspaceID, panes: [pane], tabs: [tab])),
                tabID: tab.id, paneID: nil, closeID: UUIDv7.generate(),
                time: .init(
                    utc: Date(timeIntervalSince1970: 100), bootID: "old-boot", uptimeNanoseconds: 100_000_000_000)
            )
            try await datastore.commitWorkspaceSnapshotWithUndo(close.bundle, change: .record(close.write))
        }
        for uptime in [1000, 1100] {
            let recovered = try await datastore.recoverUndoJournal(
                workspaceID: workspaceIDs[0],
                time: .init(
                    utc: Date(timeIntervalSince1970: Double(uptime)), bootID: "new-boot",
                    uptimeNanoseconds: Int64(uptime) * 1_000_000_000)
            )
            #expect(recovered.availableCloses.count == 1)
            #expect(recovered.pendingSessionIDs.isEmpty)
            for workspaceID in workspaceIDs {
                let closes = try await datastore.fetchAvailableUndoCloses(workspaceID: workspaceID)
                #expect(closes.first?.deadlineBootID == "new-boot")
                #expect(closes.first?.deadlineUptimeNanoseconds == 1_300_000_000_000)
            }
        }
        #expect(try await datastore.nextUndoDeadline(bootID: "new-boot") == 1_300_000_000_000)
        let expired = try await datastore.expireAllUndoCloses(
            time: .init(
                utc: Date(timeIntervalSince1970: 1300), bootID: "new-boot",
                uptimeNanoseconds: 1_300_000_000_000)
        )
        #expect(expired.count == 2)
        #expect(try await datastore.nextUndoDeadline(bootID: "new-boot") == nil)
    }
}
