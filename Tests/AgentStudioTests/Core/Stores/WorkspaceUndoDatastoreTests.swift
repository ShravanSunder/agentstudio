import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("Workspace undo datastore ordering", .serialized)
struct WorkspaceUndoDatastoreTests {
    @Test(
        "failed structural writes block expiry until reconciliation, local failures do not", arguments: [true, false])
    func failureBarrierProtectsExpiry(failCore: Bool) async throws {
        let workspaceID = UUIDv7.generate()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let datastore = try await preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        let pane = makePane(id: UUIDv7.generate())
        let payload = WorkspaceUndoCloseSnapshot.tab(tab: Tab(paneId: pane.id), panes: [pane], tabIndex: 0)
        let closeID = UUIDv7.generate()
        let bundle = WorkspaceSQLiteSaveBundle(workspace: .init(id: workspaceID))
        try await datastore.commitWorkspaceSnapshotWithUndo(
            bundle,
            change: .record(
                .init(
                    closeID: closeID, workspaceID: workspaceID, kind: .tab,
                    closedAt: Date(timeIntervalSince1970: 100), expiresAt: Date(timeIntervalSince1970: 400),
                    deadlineBootID: "boot-fixture", deadlineUptimeNanoseconds: 400_000_000_000,
                    snapshotVersion: 1, snapshotPayload: try JSONEncoder().encode(payload), members: payload.members
                )
            )
        )
        let beforeFailure = try await datastore.fetchAvailableUndoCloses(workspaceID: workspaceID)
        #expect(beforeFailure.map(\.closeID) == [closeID])
        let deadline = WorkspaceUndoJournalTime(
            utc: Date(timeIntervalSince1970: 400), bootID: "boot-fixture", uptimeNanoseconds: 400_000_000_000
        )

        if failCore {
            try await fixture.coreRepository.databaseWriter.write { database in
                try database.execute(
                    sql: """
                        CREATE TRIGGER reject_test_workspace_write BEFORE INSERT ON workspace
                        BEGIN SELECT RAISE(ABORT, 'injected structural failure'); END
                        """)
            }
            await #expect(throws: (any Error).self) {
                try await datastore.saveWorkspaceSnapshotBundle(bundle)
            }
            await #expect(throws: WorkspaceSQLiteDatastoreError.unreconciledStructuralSave) {
                try await datastore.expireUndoCloses(workspaceID: workspaceID, time: deadline)
            }
            let preserved = try await datastore.fetchAvailableUndoCloses(workspaceID: workspaceID)
            #expect(preserved.map(\.closeID) == [closeID])
            try await fixture.coreRepository.databaseWriter.write { database in
                try database.execute(sql: "DROP TRIGGER reject_test_workspace_write")
            }
            try await datastore.saveWorkspaceSnapshotBundle(bundle)
        } else {
            try fixture.localQueue.close()
            await #expect(throws: (any Error).self) {
                try await datastore.saveWorkspaceSnapshotBundle(bundle)
            }
        }

        let expired = try await datastore.expireUndoCloses(workspaceID: workspaceID, time: deadline)
        #expect(expired.map(\.closeID) == [closeID])
        let remaining = try await datastore.fetchAvailableUndoCloses(workspaceID: workspaceID)
        #expect(remaining.isEmpty)
    }
}
