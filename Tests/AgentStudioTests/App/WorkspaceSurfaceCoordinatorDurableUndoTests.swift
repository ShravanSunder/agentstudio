import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("Workspace command durable undo", .serialized)
struct WorkspaceSurfaceCoordinatorDurableUndoTests {
    init() { installTestCoreAtomsIfNeeded() }

    @Test("discard preserves another pane owning the same session")
    func discardPreservesSharedSession() async throws {
        let workspaceID = UUIDv7.generate()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let datastore = try preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        let store = WorkspaceStore(
            identityAtom: WorkspaceIdentityAtom(workspaceId: workspaceID),
            sqliteDatastore: datastore, startsObserving: false)
        let sessionID = ZmxSessionID.generateUUIDv7()
        let discarded = store.createPane(zmxSessionID: sessionID, residency: .backgrounded)
        let retained = store.createPane(zmxSessionID: sessionID, residency: .backgrounded)
        #expect(await store.flushAsync() == .persisted)

        try await store.discardBackgroundedPane(
            paneID: discarded.id, time: try await WorkspaceUndoJournalClock.current(),
            willPublish: { _ in }, didPublish: { _ in })

        #expect(store.paneAtom.pane(retained.id) != nil)
        #expect(try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceID).panes.map(\.id) == [retained.id])
        #expect(try fixture.coreRepository.pendingTerminalSessionIDs().isEmpty)
    }

    @Test("background discard maintains drawer ownership", arguments: [false, true])
    func discardDrawerOwnership(childOnly: Bool) async throws {
        let workspaceID = UUIDv7.generate()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let datastore = try preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        let store = WorkspaceStore(
            identityAtom: WorkspaceIdentityAtom(workspaceId: workspaceID),
            sqliteDatastore: datastore, startsObserving: false)
        let parent = store.createPane(residency: .backgrounded)
        let child = try #require(
            store.paneAtom.addDrawerPane(
                to: parent.id, parentFallbackCWD: FileManager.default.homeDirectoryForCurrentUser,
                zmxSessionID: .generateUUIDv7()))
        store.setResidency(.backgrounded, for: child.id)
        #expect(await store.flushAsync() == .persisted)

        try await store.discardBackgroundedPane(
            paneID: childOnly ? child.id : parent.id,
            time: try await WorkspaceUndoJournalClock.current(),
            willPublish: { _ in }, didPublish: { _ in })

        #expect(store.paneAtom.pane(child.id) == nil)
        #expect(try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceID).panes.count == (childOnly ? 1 : 0))
        if childOnly { #expect(store.paneAtom.pane(parent.id)?.drawer?.paneIds.isEmpty == true) }
        let pending = try fixture.coreRepository.pendingTerminalSessionIDs()
        #expect(pending.contains(try #require(child.terminalState?.zmxSessionID)))
        #expect(pending.contains(try #require(parent.terminalState?.zmxSessionID)) == !childOnly)
    }

    @Test("permanent discard commits before removing a backgrounded pane", arguments: [false, true])
    func backgroundDiscardRequiresDurability(rejectWrite: Bool) async throws {
        let workspaceID = UUIDv7.generate()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let datastore = try preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        let store = WorkspaceStore(
            identityAtom: WorkspaceIdentityAtom(workspaceId: workspaceID),
            sqliteDatastore: datastore, startsObserving: false)
        let pane = store.createPane()
        store.setResidency(.backgrounded, for: pane.id)
        #expect(await store.flushAsync() == .persisted)
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store, viewRegistry: ViewRegistry(), runtime: SessionRuntime(store: store),
            surfaceManager: HarnessSurfaceManager(), runtimeRegistry: RuntimeRegistry(),
            windowLifecycleStore: WindowLifecycleAtom(), bridgePaneAttendance: BridgePaneAttendanceAtom()
        )
        if rejectWrite {
            try await fixture.coreRepository.databaseWriter.write { database in
                try database.execute(
                    sql: """
                        CREATE TRIGGER reject_permanent_discard BEFORE DELETE ON pane
                        BEGIN SELECT RAISE(ABORT, 'injected discard failure'); END
                        """)
            }
            await #expect(throws: (any Error).self) {
                try await coordinator.execute(.purgeOrphanedPane(paneId: pane.id))
            }
            #expect(store.paneAtom.pane(pane.id) != nil)
            #expect(try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceID).panes.count == 1)
        } else {
            try await coordinator.execute(.purgeOrphanedPane(paneId: pane.id))
            #expect(store.paneAtom.pane(pane.id) == nil)
            #expect(try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceID).panes.isEmpty)
            let sessionID = try #require(pane.terminalState?.zmxSessionID)
            #expect(try fixture.coreRepository.pendingTerminalSessionIDs().contains(sessionID))
        }
        await coordinator.shutdown()
    }

    @Test("a rejected journal write leaves the app's pane and tab open")
    func failedClosePreservesLiveAppComposition() async throws {
        let workspaceID = UUIDv7.generate()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let datastore = try preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        let store = WorkspaceStore(
            identityAtom: WorkspaceIdentityAtom(workspaceId: workspaceID),
            sqliteDatastore: datastore, startsObserving: false)
        let pane = store.createPane()
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        #expect(await store.flushAsync() == .persisted)
        let manager = HarnessSurfaceManager()
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store, viewRegistry: ViewRegistry(), runtime: SessionRuntime(store: store),
            surfaceManager: manager, runtimeRegistry: RuntimeRegistry(),
            windowLifecycleStore: WindowLifecycleAtom(), bridgePaneAttendance: BridgePaneAttendanceAtom()
        )
        try await fixture.coreRepository.databaseWriter.write { database in
            try database.execute(
                sql: """
                    CREATE TRIGGER reject_app_close BEFORE INSERT ON workspace_undo_close
                    BEGIN SELECT RAISE(ABORT, 'injected journal failure'); END
                    """)
        }

        await #expect(throws: (any Error).self) {
            try await coordinator.execute(.closeTab(tabId: tab.id))
        }
        #expect(store.tabLayoutAtom.tab(tab.id) != nil)
        #expect(store.paneAtom.pane(pane.id)?.residency == .active)
        #expect(coordinator.undoStack.isEmpty)
        #expect(manager.retainedUndoPaneIDs.isEmpty)
        await coordinator.shutdown()
    }

    @Test("app close and undo use the durable journal as ownership authority")
    func appCloseAndUndoUseJournal() async throws {
        let workspaceID = UUIDv7.generate()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let datastore = try preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        let store = WorkspaceStore(
            identityAtom: WorkspaceIdentityAtom(workspaceId: workspaceID),
            sqliteDatastore: datastore, startsObserving: false)
        let pane = store.createPane()
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        #expect(await store.flushAsync() == .persisted)
        let manager = HarnessSurfaceManager()
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store, viewRegistry: ViewRegistry(), runtime: SessionRuntime(store: store),
            surfaceManager: manager, runtimeRegistry: RuntimeRegistry(),
            windowLifecycleStore: WindowLifecycleAtom(), bridgePaneAttendance: BridgePaneAttendanceAtom()
        )

        try await coordinator.execute(.closeTab(tabId: tab.id))
        #expect(store.tabLayoutAtom.tab(tab.id) == nil)
        #expect(store.paneAtom.pane(pane.id) == nil)
        #expect(try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceID).panes.isEmpty)
        let history = try await datastore.fetchAvailableUndoCloses(workspaceID: workspaceID)
        #expect(history.count == 1)
        #expect(history.first?.snapshot.panes.map(\.id) == [pane.id])
        #expect(manager.retainedUndoPaneIDs == [pane.id])

        try await coordinator.undoCloseTab()
        #expect(store.paneAtom.pane(pane.id)?.terminalState?.zmxSessionID == pane.terminalState?.zmxSessionID)
        #expect(try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceID).panes.map(\.id) == [pane.id])
        #expect(try await datastore.fetchAvailableUndoCloses(workspaceID: workspaceID).isEmpty)
        await coordinator.shutdown()
    }
}
