import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteDrawerRoundTripTests", .serialized)
struct WorkspaceSQLiteDrawerRoundTripTests {
    @Test("drawer identity ordering expansion and active child survive SQLite save load")
    func drawerIdentityOrderingExpansionAndActiveChildSurviveSQLiteSaveLoad() async throws {
        let fixture = try makeRoundTripFixture(updatedAt: Date(timeIntervalSince1970: 40))
        try await fixture.datastore.saveWorkspaceSnapshot(fixture.snapshot)

        let result = await fixture.datastore.loadWorkspaceSnapshot(preferredWorkspaceId: fixture.snapshot.id)

        guard case .loaded(let restoredSnapshot, let recoveryEvents) = result else {
            Issue.record("Expected loaded snapshot, got \(result)")
            return
        }
        #expect(recoveryEvents.isEmpty)
        let restoredParent = try #require(restoredSnapshot.panes.first { $0.id == fixture.parentPaneId })
        let restoredDrawer = try #require(restoredParent.drawer)
        let restoredTab = try #require(restoredSnapshot.tabs.first { $0.id == fixture.tabId })
        let restoredArrangement = try #require(restoredTab.arrangements.first { $0.id == fixture.arrangementId })
        let restoredDrawerView = try #require(restoredArrangement.drawerViews[restoredDrawer.drawerId])

        #expect(restoredDrawer.drawerId == fixture.drawerId)
        #expect(restoredDrawer.parentPaneId == fixture.parentPaneId)
        #expect(restoredDrawer.paneIds == fixture.drawerChildPaneIds)
        #expect(restoredDrawer.isExpanded)
        #expect(restoredDrawerView.layout.paneIds == fixture.drawerLayoutPaneIds)
        #expect(restoredDrawerView.activeChildId == fixture.activeDrawerPaneId)
    }

    @Test("drawer cursor rows are fully replaced when drawers are deleted")
    func drawerCursorRowsAreFullyReplacedWhenDrawersAreDeleted() async throws {
        let fixture = try makeRoundTripFixture(updatedAt: Date(timeIntervalSince1970: 50))
        try await fixture.datastore.saveWorkspaceSnapshot(fixture.snapshot)
        #expect(try localDrawerCursorRowCount(fixture.localQueue) == 1)
        #expect(try localArrangementDrawerCursorRowCount(fixture.localQueue) == 1)

        let store = try makeRestoredStore(from: fixture.snapshot)
        store.removePane(fixture.parentPaneId)
        let snapshotAfterDelete = WorkspacePersistenceTransformer.makeLiveSQLiteSnapshot(
            identityAtom: store.identityAtom,
            windowMemoryAtom: store.windowMemoryAtom,
            repositoryTopologyAtom: store.repositoryTopologyAtom,
            workspacePaneAtom: store.paneAtom,
            workspaceTabLayoutAtom: store.tabLayoutAtom,
            persistedAt: Date(timeIntervalSince1970: 51)
        )

        try await fixture.datastore.saveWorkspaceSnapshot(snapshotAfterDelete)

        #expect(try localDrawerCursorRowCount(fixture.localQueue) == 0)
        #expect(try localArrangementDrawerCursorRowCount(fixture.localQueue) == 0)
    }
}

private struct DrawerRoundTripFixture {
    var datastore: WorkspaceSQLiteDatastore
    var localQueue: DatabaseQueue
    var snapshot: WorkspaceSQLiteSnapshot
    var parentPaneId: UUID
    var drawerId: UUID
    var drawerChildPaneIds: [UUID]
    var drawerLayoutPaneIds: [UUID]
    var activeDrawerPaneId: UUID
    var tabId: UUID
    var arrangementId: UUID
}

@MainActor
private func makeRoundTripFixture(updatedAt: Date) throws -> DrawerRoundTripFixture {
    let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
        label: "AgentStudio.sqlite.drawer-round-trip.core.\(UUID().uuidString)")
    let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
        label: "AgentStudio.sqlite.drawer-round-trip.local.\(UUID().uuidString)")
    try WorkspaceCoreMigrations.migrate(coreQueue)
    try WorkspaceLocalMigrations.migrate(localQueue)
    let datastore = WorkspaceSQLiteDatastore(
        coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
        makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: localQueue) }
    )
    let store = WorkspaceStore(
        persistor: WorkspacePersistor(
            workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
    )
    let parentPane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
    store.appendTab(Tab(paneId: parentPane.id))
    let firstDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
    let secondDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))

    store.moveDrawerPane(
        firstDrawerPane.id,
        in: parentPane.id,
        target: .rowSlot(row: .top, insertionIndex: 2),
        sizingMode: .proportional
    )

    let parentWithDrawer = try #require(store.pane(parentPane.id))
    let drawer = try #require(parentWithDrawer.drawer)
    let tab = try #require(store.tabLayoutAtom.tabContaining(paneId: parentPane.id))
    let arrangement = try #require(tab.arrangements.first)
    let snapshot = WorkspacePersistenceTransformer.makeLiveSQLiteSnapshot(
        identityAtom: store.identityAtom,
        windowMemoryAtom: store.windowMemoryAtom,
        repositoryTopologyAtom: store.repositoryTopologyAtom,
        workspacePaneAtom: store.paneAtom,
        workspaceTabLayoutAtom: store.tabLayoutAtom,
        persistedAt: updatedAt
    )

    return .init(
        datastore: datastore,
        localQueue: localQueue,
        snapshot: snapshot,
        parentPaneId: parentPane.id,
        drawerId: drawer.drawerId,
        drawerChildPaneIds: [firstDrawerPane.id, secondDrawerPane.id],
        drawerLayoutPaneIds: [secondDrawerPane.id, firstDrawerPane.id],
        activeDrawerPaneId: firstDrawerPane.id,
        tabId: tab.id,
        arrangementId: arrangement.id
    )
}

@MainActor
private func makeRestoredStore(from snapshot: WorkspaceSQLiteSnapshot) throws -> WorkspaceStore {
    let store = WorkspaceStore(
        persistor: WorkspacePersistor(
            workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
    )
    let state = WorkspacePersistenceTransformer.persistableState(from: snapshot)
    store.hydrateWorkspaceState(state)
    return store
}

private func localDrawerCursorRowCount(_ queue: DatabaseQueue) throws -> Int {
    try queue.read { database in
        try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM local_drawer_cursor") ?? 0
    }
}

private func localArrangementDrawerCursorRowCount(_ queue: DatabaseQueue) throws -> Int {
    try queue.read { database in
        try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM local_arrangement_drawer_cursor") ?? 0
    }
}
