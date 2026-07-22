import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct UIStateStoreTests {
    @Test
    func flushAndRestoreRoundTripsMainWindowSidebarState() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let datastore = try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        let atom = WorkspaceSidebarState()
        let store = UIStateStore(atom: atom, sqliteDatastore: datastore)
        atom.setFilterText("agent")
        atom.setFilterVisible(true)
        atom.setSidebarCollapsed(true)
        atom.setSidebarSurface(.inbox)
        atom.setSidebarHasFocus(true)

        try await store.flushAsync(for: workspaceId)
        let restoredAtom = WorkspaceSidebarState()
        await UIStateStore(atom: restoredAtom, sqliteDatastore: datastore).restoreAsync(for: workspaceId)

        #expect(restoredAtom.filterText == "agent")
        #expect(restoredAtom.isFilterVisible)
        #expect(restoredAtom.sidebarCollapsed)
        #expect(restoredAtom.sidebarSurface == .inbox)
        #expect(restoredAtom.sidebarHasFocus == false)
    }

    @Test
    func missingSQLiteRowResetsExistingStateToTypedDefaults() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let atom = WorkspaceSidebarState()
        atom.setFilterText("stale")
        atom.setFilterVisible(true)
        atom.setSidebarCollapsed(true)
        atom.setSidebarSurface(.inbox)
        atom.setSidebarHasFocus(true)

        await UIStateStore(
            atom: atom,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        ).restoreAsync(for: workspaceId)

        #expect(atom.filterText.isEmpty)
        #expect(atom.isFilterVisible == false)
        #expect(atom.sidebarCollapsed == false)
        #expect(atom.sidebarSurface == .repos)
        #expect(atom.sidebarHasFocus == false)
    }

    @Test
    func unavailableSQLiteResetsDefaultsAndReportsRecovery() async throws {
        let workspaceId = UUID()
        let atom = WorkspaceSidebarState()
        atom.setFilterText("stale")
        atom.setSidebarSurface(.inbox)
        var reportedRecoveries: [PersistenceRecoveryEvent] = []

        await UIStateStore(
            atom: atom,
            sqliteDatastore: try workspaceSQLiteDatastore(from: failingWorkspaceLocalSQLiteBackend()),
            recoveryReporter: { reportedRecoveries.append($0) }
        ).restoreAsync(for: workspaceId)

        #expect(atom.filterText.isEmpty)
        #expect(atom.sidebarSurface == .repos)
        #expect(
            reportedRecoveries.contains { recovery in
                recovery.store == .uiState
                    && recovery.workspaceId == workspaceId
                    && recovery.recovery == .resetToDefaults
            })
    }

    @Test
    func observedSidebarMutationAutosavesSQLite() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let atom = WorkspaceSidebarState()
        let clock = TestPushClock()
        let store = UIStateStore(
            atom: atom,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend),
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )
        await store.restoreAsync(for: workspaceId)
        store.startObserving()

        atom.setFilterText("terminal")
        atom.setSidebarSurface(.inbox)
        await clock.waitForPendingSleepCount()
        clock.advance(by: .milliseconds(10))

        await assertEventuallyMain("sidebar state should autosave") {
            guard let state = try? fixture.repository.fetchSidebarState() else { return false }
            return state.filterText == "terminal" && state.sidebarSurface == .inbox
        }
    }

    @Test
    func editorStateIsNotOwnedOrObservedByUIStateStore() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let preferenceAtom = EditorPreferenceAtom()
        let runtimeAtom = EditorChooserRuntimeAtom()
        let editorChooser = EditorChooserState(preferenceAtom: preferenceAtom, runtimeAtom: runtimeAtom)
        let clock = TestPushClock()
        let store = UIStateStore(
            atom: WorkspaceSidebarState(),
            editorChooserState: editorChooser,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend),
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )
        await store.restoreAsync(for: workspaceId)
        store.startObserving()

        preferenceAtom.setBookmarkedEditor("cursor")
        runtimeAtom.setOpenEditorPane(UUID())
        runtimeAtom.setAvailableTargets(ExternalEditorTarget.curatedOrder)
        for _ in 0..<20 { await Task.yield() }

        #expect(clock.pendingSleepCount == 0)
        #expect(try fixture.repository.hasSidebarState() == false)
    }

    @Test
    func restoreCancelsPendingSaveFromPreviousWorkspaceContext() async throws {
        let workspaceAId = UUID()
        let workspaceBId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceAId)
        let atom = WorkspaceSidebarState()
        let clock = TestPushClock()
        let store = UIStateStore(
            atom: atom,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend),
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )
        await store.restoreAsync(for: workspaceAId)
        store.startObserving()
        atom.setFilterText("stale-workspace-draft")
        await clock.waitForPendingSleepCount()

        await store.restoreAsync(for: workspaceBId)
        clock.advance(by: .milliseconds(10))
        await Task.yield()

        #expect(try fixture.repository.hasSidebarState() == false)
    }

    @Test
    func observationIsExplicitlyArmed() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let store = UIStateStore(
            atom: WorkspaceSidebarState(),
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        )

        #expect(store.isAutosaveObservationActive == false)
        await store.restoreAsync(for: workspaceId)
        #expect(store.isAutosaveObservationActive == false)
        store.startObserving()
        #expect(store.isAutosaveObservationActive)
    }
}
