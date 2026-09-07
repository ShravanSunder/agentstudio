import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("Workspace atomic undo restore")
struct WorkspaceUndoCloseRestoreTests {
    @Test("undo and expiry have only one winner", arguments: [true, false])
    func undoAndExpiryHaveOneWinner(restoreFirst: Bool) throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let (open, closed, closeID) = try closeFixtureTab(fixture)
        let beforeDeadline = WorkspaceUndoJournalTime(
            utc: Date(timeIntervalSince1970: 399), bootID: "boot-fixture", uptimeNanoseconds: 399_000_000_000
        )
        let deadline = WorkspaceUndoJournalTime(
            utc: Date(timeIntervalSince1970: 400), bootID: "boot-fixture", uptimeNanoseconds: 400_000_000_000
        )

        if restoreFirst {
            try replace(fixture, snapshot: open, change: .restore(closeID: closeID, time: beforeDeadline))
            let expired = try fixture.repository.expireUndoCloses(workspaceID: open.id, time: deadline)
            #expect(expired.isEmpty)
            let restored = try fixture.repository.fetchPaneGraph(workspaceId: open.id)
            let expectedGraph = try WorkspaceSQLiteStateBridge.paneGraphRecord(from: open)
            #expect(restored == expectedGraph)
        } else {
            let expired = try fixture.repository.expireUndoCloses(workspaceID: open.id, time: deadline)
            #expect(expired.map(\.closeID) == [closeID])
            #expect(throws: WorkspaceUndoJournalFailure.undoUnavailable) {
                try replace(fixture, snapshot: open, change: .restore(closeID: closeID, time: beforeDeadline))
            }
            #expect(try fixture.repository.fetchPaneGraph(workspaceId: closed.id).panes.isEmpty)
        }
        #expect(try fixture.repository.fetchAvailableUndoCloses(workspaceID: open.id).isEmpty)
    }

    @Test("restore that omits owned panes rolls back without consuming undo")
    func invalidRestorePreservesUndo() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let (open, closed, closeID) = try closeFixtureTab(fixture)

        #expect(throws: WorkspaceUndoJournalFailure.restoreMembershipMismatch) {
            try replace(
                fixture,
                snapshot: closed,
                change: .restore(
                    closeID: closeID,
                    time: .init(
                        utc: Date(timeIntervalSince1970: 200), bootID: "boot-fixture",
                        uptimeNanoseconds: 200_000_000_000)
                )
            )
        }
        #expect(try fixture.repository.fetchAvailableUndoCloses(workspaceID: open.id).map(\.closeID) == [closeID])
        #expect(try fixture.repository.fetchPaneGraph(workspaceId: open.id).panes.isEmpty)
    }

    private func closeFixtureTab(
        _ fixture: WorkspaceCoreTopologyRepositoryFixture
    ) throws -> (WorkspaceSQLiteSnapshot, WorkspaceSQLiteSnapshot, UUID) {
        let timestamp = Date(timeIntervalSince1970: 100)
        let pane = Pane(
            id: UUIDv7.generate(),
            content: .terminal(
                TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())
            ),
            metadata: PaneMetadata(createdAt: timestamp)
        )
        let tab = Tab(id: UUIDv7.generate(), paneId: pane.id)
        let open = WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(), panes: [pane], tabs: [tab], createdAt: timestamp, updatedAt: timestamp
        )
        let closed = WorkspaceSQLiteSnapshot(id: open.id, createdAt: timestamp, updatedAt: timestamp)
        let closeID = UUIDv7.generate()
        let payload = WorkspaceUndoCloseSnapshot.tab(tab: tab, panes: [pane], tabIndex: 0)
        try replace(fixture, snapshot: open, change: nil)
        try replace(
            fixture,
            snapshot: closed,
            change: .record(
                .init(
                    closeID: closeID, workspaceID: open.id, kind: .tab,
                    closedAt: Date(timeIntervalSince1970: 100), expiresAt: Date(timeIntervalSince1970: 400),
                    deadlineBootID: "boot-fixture", deadlineUptimeNanoseconds: 400_000_000_000,
                    snapshotVersion: 1, snapshotPayload: try JSONEncoder().encode(payload), members: payload.members
                )
            )
        )
        return (open, closed, closeID)
    }

    private func replace(
        _ fixture: WorkspaceCoreTopologyRepositoryFixture,
        snapshot: WorkspaceSQLiteSnapshot,
        change: WorkspaceUndoJournalChange?
    ) throws {
        try fixture.repository.replaceWorkspaceSnapshot(
            workspace: WorkspaceSQLiteStateBridge.workspaceRecord(from: snapshot),
            paneGraph: WorkspaceSQLiteStateBridge.paneGraphRecord(from: snapshot),
            tabShells: WorkspaceSQLiteStateBridge.tabShellRecords(from: snapshot),
            tabGraph: WorkspaceSQLiteStateBridge.tabGraphRecord(from: snapshot),
            undoChange: change
        )
    }
}
