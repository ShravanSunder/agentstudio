import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore

/// Failure and ordering boundaries of the drawer presentation local save,
/// against real SQLite: a save that cannot establish retention membership, or
/// that arrives after a newer save, must never persist or acknowledge stale
/// drawer choices.
@MainActor
@Suite("Workspace drawer presentation save boundary", .serialized)
struct WorkspaceDrawerPresentationSaveBoundaryTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    private struct SaveBoundaryFixture {
        let workspaceId: UUID
        let coreQueue: DatabaseQueue
        let localQueue: DatabaseQueue
        let probeRecorder: DrawerPresentationProbeRecorder
        let datastore: WorkspaceSQLiteDatastoreActor
        let store: WorkspaceStore

        func storedRatios() throws -> [UUID: Double] {
            try WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
                .fetchDrawerPresentationRecords()
                .reduce(into: [UUID: Double]()) { result, record in
                    result[record.ownerPaneId] = record.normalHeightRatio
                }
        }
    }

    private func makeFixture() async throws -> SaveBoundaryFixture {
        let workspaceId = UUIDv7.generate()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "drawer-presentation.boundary.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "drawer-presentation.boundary.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let probeRecorder = DrawerPresentationProbeRecorder()
        let datastore = try await preparedWorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            preparedApplicationLocalRepository: WorkspaceLocalRepository(
                workspaceId: workspaceId,
                databaseWriter: localQueue
            ),
            probe: { event in await probeRecorder.record(event) }
        )
        let store = WorkspaceStore(
            identityAtom: WorkspaceIdentityAtom(workspaceId: workspaceId),
            sqliteDatastore: datastore,
            clock: TestPushClock()
        )
        return SaveBoundaryFixture(
            workspaceId: workspaceId,
            coreQueue: coreQueue,
            localQueue: localQueue,
            probeRecorder: probeRecorder,
            datastore: datastore,
            store: store
        )
    }

    private func appendTabbedPane(to store: WorkspaceStore) -> Pane {
        let pane = store.createPane()
        store.appendTab(Tab(paneId: pane.id))
        return pane
    }

    @Test("a retention-membership failure fails the local save without pruning, success, or clearing dirty")
    func membershipFailureTakesLocalSaveFailurePath() async throws {
        // Arrange
        let fixture = try await makeFixture()
        let paneA = appendTabbedPane(to: fixture.store)
        fixture.store.paneAtom.setDrawerNormalHeightRatio(0.4, forOwner: paneA.id)
        #expect(await fixture.store.flushAsync() == .persisted)
        // Break only the undo-member pane column the retention read uses; the
        // core save's session-ownership queries do not read it.
        try await fixture.coreQueue.write { database in
            try database.execute(
                sql: "ALTER TABLE workspace_undo_close_member RENAME COLUMN pane_id TO unreadable_pane_id"
            )
        }
        let paneB = appendTabbedPane(to: fixture.store)
        fixture.store.paneAtom.setDrawerNormalHeightRatio(0.6, forOwner: paneA.id)
        await fixture.probeRecorder.reset()

        // Act
        let outcome = await fixture.store.flushAsync()

        // Assert
        #expect(!outcome.succeeded)
        #expect(fixture.store.isDirty)
        #expect(try fixture.storedRatios() == [paneA.id: 0.4])
        let persistedPaneIds = try WorkspaceCoreRepository(databaseWriter: fixture.coreQueue)
            .fetchPaneGraph(workspaceId: fixture.workspaceId).panes.map(\.id)
        #expect(Set(persistedPaneIds) == [paneA.id, paneB.id])
        let events = await fixture.probeRecorder.events
        #expect(events.contains(.saveWorkspaceSnapshotFailed))
        #expect(!events.contains(.saveWorkspaceSnapshotSucceeded))
    }
}

actor DrawerPresentationProbeRecorder {
    private(set) var events: [WorkspaceSQLiteDatastoreActor.ProbeEvent] = []

    func record(_ event: WorkspaceSQLiteDatastoreActor.ProbeEvent) {
        events.append(event)
    }

    func reset() {
        events.removeAll()
    }
}
