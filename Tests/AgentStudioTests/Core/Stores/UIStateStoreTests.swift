import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct UIStateStoreTests {
    private let tempDir: URL
    private let persistor: WorkspacePersistor

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "ui-state-store-tests-\(UUID().uuidString)")
        persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
    }

    @Test
    func flushAndRestore_roundTripsPersistedUIState() async throws {
        let workspaceId = UUID()
        let atom = WorkspaceSidebarState()
        let uiStateStore = UIStateStore(atom: atom, editorChooserState: EditorChooserState(), persistor: persistor)

        atom.setFilterText("terminal")
        atom.setFilterVisible(true)
        atom.setSidebarCollapsed(true)
        atom.setSidebarSurface(.inbox)
        atom.setSidebarHasFocus(true)

        try await uiStateStore.flushAsync(for: workspaceId)

        let restoredAtom = WorkspaceSidebarState()
        let restoredStore = UIStateStore(
            atom: restoredAtom,
            editorChooserState: EditorChooserState(),
            persistor: persistor
        )
        await restoredStore.restoreAsync(for: workspaceId)

        #expect(restoredAtom.filterText == "terminal")
        #expect(restoredAtom.isFilterVisible)
        #expect(restoredAtom.sidebarCollapsed)
        #expect(restoredAtom.sidebarSurface == .inbox)
        #expect(restoredAtom.sidebarHasFocus == false)
    }

    @Test
    func flushAndRestore_roundTripsThroughLocalSQLite() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let atom = WorkspaceSidebarState()
        let uiStateStore = UIStateStore(
            atom: atom,
            editorChooserState: EditorChooserState(),
            persistor: persistor,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        )

        atom.setFilterText("sqlite")
        atom.setFilterVisible(true)
        atom.setSidebarCollapsed(true)
        atom.setSidebarSurface(.inbox)
        atom.setSidebarHasFocus(true)

        try await uiStateStore.flushAsync(for: workspaceId)

        let storedState = try #require(try fixture.repository.fetchSidebarState())
        #expect(storedState.filterText == "sqlite")
        #expect(storedState.isFilterVisible)
        #expect(storedState.sidebarCollapsed)
        #expect(storedState.sidebarSurface == .inbox)
        guard case .missing = persistor.loadUI(for: workspaceId) else {
            Issue.record("SQLite-backed UI state flush should not write the legacy JSON sidecar")
            return
        }

        let restoredAtom = WorkspaceSidebarState()
        let restoredStore = UIStateStore(
            atom: restoredAtom,
            editorChooserState: EditorChooserState(),
            persistor: persistor,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        )
        await restoredStore.restoreAsync(for: workspaceId)

        #expect(restoredAtom.filterText == "sqlite")
        #expect(restoredAtom.isFilterVisible)
        #expect(restoredAtom.sidebarCollapsed)
        #expect(restoredAtom.sidebarSurface == .inbox)
        #expect(restoredAtom.sidebarHasFocus == false)
    }

    @Test
    func restoreWithSQLiteBackendImportsLegacyJSONWhenLaneIsMissing() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        try persistor.saveUI(
            .init(
                workspaceId: workspaceId,
                filterText: "legacy",
                isFilterVisible: true,
                sidebarCollapsed: true,
                sidebarSurface: .inbox
            )
        )
        let atom = WorkspaceSidebarState()
        let store = UIStateStore(
            atom: atom,
            editorChooserState: EditorChooserState(),
            persistor: persistor,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        )

        await store.restoreAsync(for: workspaceId)

        #expect(atom.filterText == "legacy")
        #expect(atom.isFilterVisible)
        #expect(atom.sidebarCollapsed)
        #expect(atom.sidebarSurface == .inbox)
        #expect(try fixture.repository.hasSidebarState())
    }

    @Test
    func restoreWithSQLiteBackendResetsWhenSQLiteSidebarLaneFailsInsteadOfReplayingLegacyJSON() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let atom = WorkspaceSidebarState()
        let store = UIStateStore(
            atom: atom,
            editorChooserState: EditorChooserState(),
            persistor: persistor,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        )
        atom.setFilterText("sqlite")
        atom.setFilterVisible(true)
        atom.setSidebarCollapsed(true)
        atom.setSidebarSurface(.inbox)
        try await store.flushAsync(for: workspaceId)
        try persistor.saveUI(
            .init(
                workspaceId: workspaceId,
                filterText: "stale",
                isFilterVisible: true,
                sidebarCollapsed: true,
                sidebarSurface: .inbox
            )
        )
        try await fixture.databaseQueue.write { database in
            try database.drop(table: "local_sidebar_state")
        }

        let restoredAtom = WorkspaceSidebarState()
        let restoredStore = UIStateStore(
            atom: restoredAtom,
            editorChooserState: EditorChooserState(),
            persistor: persistor,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        )
        await restoredStore.restoreAsync(for: workspaceId)

        #expect(restoredAtom.filterText.isEmpty)
        #expect(restoredAtom.filterText != "stale")
        #expect(restoredAtom.isFilterVisible == false)
        #expect(restoredAtom.sidebarCollapsed == false)
        #expect(restoredAtom.sidebarSurface == .repos)
        #expect(!restoredStore.canArchiveLegacyUIFile)
    }

    @Test
    func unavailableSQLiteBackendResetsUIStateAndBlocksLegacyArchiveReadiness() async throws {
        let workspaceId = UUID()
        try persistor.saveUI(
            .init(
                workspaceId: workspaceId,
                filterText: "legacy",
                isFilterVisible: true,
                sidebarCollapsed: true,
                sidebarSurface: .inbox
            )
        )
        let atom = WorkspaceSidebarState()
        let store = UIStateStore(
            atom: atom,
            editorChooserState: EditorChooserState(),
            persistor: persistor,
            sqliteDatastore: try workspaceSQLiteDatastore(from: failingWorkspaceLocalSQLiteBackend())
        )

        await store.restoreAsync(for: workspaceId)

        #expect(atom.filterText.isEmpty)
        #expect(atom.isFilterVisible == false)
        #expect(atom.sidebarCollapsed == false)
        #expect(atom.sidebarSurface == .repos)
        #expect(!store.canArchiveLegacyUIFile)
    }

    @Test
    func missingSQLiteSidebarLaneAfterCompletedImportResetsAndBlocksLegacyArchive() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let atom = WorkspaceSidebarState()
        let store = UIStateStore(
            atom: atom,
            editorChooserState: EditorChooserState(),
            persistor: persistor,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        )
        atom.setFilterText("sqlite")
        atom.setFilterVisible(true)
        atom.setSidebarCollapsed(true)
        atom.setSidebarSurface(.inbox)
        try await store.flushAsync(for: workspaceId)
        try persistor.saveUI(
            .init(
                workspaceId: workspaceId,
                filterText: "stale",
                isFilterVisible: true,
                sidebarCollapsed: true,
                sidebarSurface: .inbox
            )
        )
        try await fixture.databaseQueue.write { database in
            try database.execute(
                sql: "DELETE FROM local_sidebar_state WHERE workspace_id = ?",
                arguments: [workspaceId.uuidString]
            )
        }
        let restoredAtom = WorkspaceSidebarState()
        let restoredStore = UIStateStore(
            atom: restoredAtom,
            editorChooserState: EditorChooserState(),
            persistor: persistor,
            sqliteDatastore: try workspaceSQLiteDatastore(
                from: workspaceLocalSQLiteBackendWithImportedLegacyLanes(repository: fixture.repository))
        )

        await restoredStore.restoreAsync(for: workspaceId)

        #expect(restoredAtom.filterText.isEmpty)
        #expect(restoredAtom.filterText != "stale")
        #expect(restoredAtom.sidebarSurface == .repos)
        #expect(!restoredStore.canArchiveLegacyUIFile)
    }

    @Test
    func missingSQLiteSidebarLaneAfterCompletedImportDoesNotBlockArchiveWhenLegacyUIFileIsAbsent() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let restoredAtom = WorkspaceSidebarState()
        let restoredStore = UIStateStore(
            atom: restoredAtom,
            editorChooserState: EditorChooserState(),
            persistor: persistor,
            sqliteDatastore: try workspaceSQLiteDatastore(
                from: workspaceLocalSQLiteBackendWithImportedLegacyLanes(repository: fixture.repository))
        )

        await restoredStore.restoreAsync(for: workspaceId)

        #expect(restoredAtom.filterText.isEmpty)
        #expect(restoredAtom.sidebarSurface == .repos)
        #expect(restoredStore.canArchiveLegacyUIFile)
    }

    @Test
    func flush_operatesOnTheProvidedLiveAtomScope() async throws {
        let workspaceId = UUID()
        let atom = WorkspaceSidebarState()
        let store = UIStateStore(atom: atom, editorChooserState: EditorChooserState(), persistor: persistor)

        atom.setFilterText("agent")
        atom.setFilterVisible(true)
        atom.setSidebarCollapsed(true)
        atom.setSidebarSurface(.inbox)
        atom.setSidebarHasFocus(true)

        try await store.flushAsync(for: workspaceId)

        let restoredAtom = WorkspaceSidebarState()
        await UIStateStore(
            atom: restoredAtom,
            editorChooserState: EditorChooserState(),
            persistor: persistor
        ).restoreAsync(for: workspaceId)

        #expect(restoredAtom.filterText == "agent")
        #expect(restoredAtom.isFilterVisible)
        #expect(restoredAtom.sidebarCollapsed)
        #expect(restoredAtom.sidebarSurface == .inbox)
        #expect(restoredAtom.sidebarHasFocus == false)
    }

    @Test
    func restore_corruptUIFile_fallsBackToDefaults() async throws {
        let workspaceId = UUID()
        let corruptURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        try "not json".write(to: corruptURL, atomically: true, encoding: .utf8)

        let atom = WorkspaceSidebarState()
        var reportedRecovery: PersistenceRecoveryEvent?
        let store = UIStateStore(
            atom: atom,
            editorChooserState: EditorChooserState(),
            persistor: persistor,
            recoveryReporter: { reportedRecovery = $0 }
        )

        await store.restoreAsync(for: workspaceId)

        #expect(atom.filterText.isEmpty)
        #expect(!atom.isFilterVisible)
        #expect(atom.sidebarCollapsed == false)
        #expect(atom.sidebarSurface == .repos)
        #expect(atom.sidebarHasFocus == false)
        #expect(reportedRecovery?.store == .uiState)
        #expect(reportedRecovery?.workspaceId == workspaceId)
        #expect(reportedRecovery?.recovery == .quarantinedAndReset)
        let quarantinedFiles = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("\(workspaceId.uuidString).workspace.ui.corrupt-")
        }
        #expect(quarantinedFiles.count == 1)
    }

    @Test
    func flushFailure_reportsSaveFailedRecovery() async {
        let workspaceId = UUID()
        let blockedDirectoryURL = FileManager.default.temporaryDirectory
            .appending(path: "ui-state-blocked-\(UUID().uuidString)")
        try? Data("not-a-directory".utf8).write(to: blockedDirectoryURL, options: .atomic)
        let atom = WorkspaceSidebarState()
        var reportedRecovery: PersistenceRecoveryEvent?
        let store = UIStateStore(
            atom: atom,
            editorChooserState: EditorChooserState(),
            persistor: WorkspacePersistor(workspacesDir: blockedDirectoryURL),
            recoveryReporter: { reportedRecovery = $0 }
        )

        do {
            try await store.flushAsync(for: workspaceId)
            Issue.record("Expected UI state flush to fail")
        } catch {
            // Expected path.
        }

        #expect(reportedRecovery?.store == .uiState)
        #expect(reportedRecovery?.workspaceId == workspaceId)
        #expect(reportedRecovery?.recovery == .saveFailed)
    }

    @Test
    func restore_legacyShowMinimizedBarsField_isIgnored() async throws {
        let workspaceId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "workspaceId": "\(workspaceId.uuidString)",
                "filterText": "",
                "isFilterVisible": false,
                "showMinimizedBars": false,
                "sidebarCollapsed": true
            }
            """
        let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        try Data(json.utf8).write(to: uiURL, options: .atomic)

        let atom = WorkspaceSidebarState()
        let store = UIStateStore(atom: atom, editorChooserState: EditorChooserState(), persistor: persistor)

        await store.restoreAsync(for: workspaceId)

        #expect(atom.sidebarCollapsed)
    }

    @Test
    func restore_missingSidebarCompositionFields_defaultsToCollapsedFalseAndReposSurface() async throws {
        let workspaceId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "workspaceId": "\(workspaceId.uuidString)",
                "filterText": "",
                "isFilterVisible": false
            }
            """
        let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        try Data(json.utf8).write(to: uiURL, options: .atomic)

        let atom = WorkspaceSidebarState()
        await UIStateStore(
            atom: atom,
            editorChooserState: EditorChooserState(),
            persistor: persistor
        ).restoreAsync(for: workspaceId)

        #expect(atom.sidebarCollapsed == false)
        #expect(atom.sidebarSurface == .repos)
        #expect(atom.sidebarHasFocus == false)
    }

    @Test
    func restore_corruptFilterFields_preservesOtherUIState() async throws {
        let workspaceId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "workspaceId": "\(workspaceId.uuidString)",
                "filterText": 42,
                "isFilterVisible": "bad-value",
                "showMinimizedBars": false,
                "sidebarCollapsed": true,
                "sidebarSurface": "inbox"
            }
            """
        let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        try Data(json.utf8).write(to: uiURL, options: .atomic)

        let atom = WorkspaceSidebarState()
        await UIStateStore(
            atom: atom,
            editorChooserState: EditorChooserState(),
            persistor: persistor
        ).restoreAsync(for: workspaceId)

        #expect(atom.filterText.isEmpty)
        #expect(atom.isFilterVisible == false)
        #expect(atom.sidebarCollapsed)
        #expect(atom.sidebarSurface == .inbox)
    }

    @Test
    func editorChooserState_isNotOwnedByUIStatePersistence() async throws {
        let workspaceId = UUID()
        let atom = WorkspaceSidebarState()
        let editorChooser = EditorChooserState()
        let store = UIStateStore(atom: atom, editorChooserState: editorChooser, persistor: persistor)

        editorChooser.setBookmarkedEditor("cursor")
        editorChooser.setOpenEditorPane(UUID())

        try await store.flushAsync(for: workspaceId)
        let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        let persistedPayload = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: uiURL)) as? [String: Any]
        )
        let persistedEditorChooserState = persistedPayload["editorChooserState"] as? [String: Any]
        #expect(persistedEditorChooserState?["bookmarkedEditorId"] == nil)
        #expect(persistedEditorChooserState?["openForPaneId"] == nil)

        let restoredAtom = WorkspaceSidebarState()
        let restoredEditorChooser = EditorChooserState()
        await UIStateStore(
            atom: restoredAtom,
            editorChooserState: restoredEditorChooser,
            persistor: persistor
        ).restoreAsync(for: workspaceId)

        #expect(restoredEditorChooser.bookmarkedEditorId == nil)
        #expect(restoredEditorChooser.openForPaneId == nil)
    }

    @Test
    func directEditorPreferenceMutation_doesNotAutosaveUIState() async throws {
        let workspaceId = UUID()
        let atom = WorkspaceSidebarState()
        let preferenceAtom = EditorPreferenceAtom()
        let editorChooser = EditorChooserState(preferenceAtom: preferenceAtom)
        let store = UIStateStore(
            atom: atom,
            editorChooserState: editorChooser,
            persistor: persistor,
            persistDebounceDuration: .zero
        )
        await store.restoreAsync(for: workspaceId)
        store.startObserving()

        preferenceAtom.setBookmarkedEditor("cursor")

        await assertEventuallyMain("editor preference mutation should not autosave UI state") {
            if case .missing = persistor.loadUI(for: workspaceId) { return true }
            return false
        }
    }

    @Test
    func editorChooserRuntimeMutation_doesNotAutosaveUIState() async {
        let workspaceId = UUID()
        let atom = WorkspaceSidebarState()
        let runtimeAtom = EditorChooserRuntimeAtom()
        let editorChooser = EditorChooserState(runtimeAtom: runtimeAtom)
        let clock = TestPushClock()
        let store = UIStateStore(
            atom: atom,
            editorChooserState: editorChooser,
            persistor: persistor,
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )
        await store.restoreAsync(for: workspaceId)
        store.startObserving()

        runtimeAtom.setOpenEditorPane(UUID())
        runtimeAtom.setAvailableTargets(ExternalEditorTarget.curatedOrder)
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(clock.pendingSleepCount == 0)
        guard case .missing = persistor.loadUI(for: workspaceId) else {
            Issue.record("Runtime-only editor chooser mutations must not autosave UI state")
            return
        }
    }

    @Test
    func restore_missingEditorChooserState_defaultsToEmptyState() async throws {
        let workspaceId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "workspaceId": "\(workspaceId.uuidString)",
                "filterText": "",
                "isFilterVisible": false
            }
            """
        let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        try Data(json.utf8).write(to: uiURL, options: .atomic)

        let atom = WorkspaceSidebarState()
        let editorChooser = EditorChooserState()
        await UIStateStore(atom: atom, editorChooserState: editorChooser, persistor: persistor).restoreAsync(
            for: workspaceId)

        #expect(editorChooser.bookmarkedEditorId == nil)
        #expect(editorChooser.openForPaneId == nil)
    }

    @Test
    func restore_persistedOpenEditorPane_isResetToNil() async throws {
        let workspaceId = UUID()
        let persistedPaneId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "workspaceId": "\(workspaceId.uuidString)",
                "filterText": "",
                "isFilterVisible": false,
                "editorChooserState": {
                    "openForPaneId": "\(persistedPaneId.uuidString)",
                    "bookmarkedEditorId": "cursor"
                }
            }
            """
        let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        try Data(json.utf8).write(to: uiURL, options: .atomic)

        let atom = WorkspaceSidebarState()
        let editorChooser = EditorChooserState()
        await UIStateStore(atom: atom, editorChooserState: editorChooser, persistor: persistor).restoreAsync(
            for: workspaceId)

        #expect(editorChooser.bookmarkedEditorId == nil)
        #expect(editorChooser.openForPaneId == nil)
    }

    @Test
    func restore_corruptEditorChooserState_preservesOtherUIState() async throws {
        let workspaceId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "workspaceId": "\(workspaceId.uuidString)",
                "filterText": "terminal",
                "isFilterVisible": true,
                "editorChooserState": "bad-value"
            }
            """
        let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        try Data(json.utf8).write(to: uiURL, options: .atomic)

        let atom = WorkspaceSidebarState()
        let editorChooser = EditorChooserState()
        await UIStateStore(atom: atom, editorChooserState: editorChooser, persistor: persistor).restoreAsync(
            for: workspaceId)

        #expect(atom.filterText == "terminal")
        #expect(atom.isFilterVisible)
        #expect(editorChooser.bookmarkedEditorId == nil)
        #expect(editorChooser.openForPaneId == nil)
    }

    @Test
    func restore_cancelsPendingDebouncedSaveForPreviousWorkspace() async throws {
        let workspaceAId = UUID()
        let workspaceBId = UUID()
        try persistor.saveUI(
            .init(
                workspaceId: workspaceBId,
                filterText: "workspace-b",
                isFilterVisible: true
            )
        )
        let atom = WorkspaceSidebarState()
        let clock = TestPushClock()
        let store = UIStateStore(
            atom: atom,
            editorChooserState: EditorChooserState(),
            persistor: persistor,
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )

        await store.restoreAsync(for: workspaceAId)
        store.startObserving()
        atom.setFilterText("workspace-a-draft")
        await clock.waitForPendingSleepCount()
        await store.restoreAsync(for: workspaceBId)
        clock.advance(by: .milliseconds(10))
        await Task.yield()

        guard case .missing = persistor.loadUI(for: workspaceAId) else {
            Issue.record("Expected stale workspace A debounce to be cancelled")
            return
        }
    }

    @Test
    func autosaveObservationStateIsExplicitlyArmed() async {
        let workspaceId = UUID()
        let store = UIStateStore(
            atom: WorkspaceSidebarState(),
            editorChooserState: EditorChooserState(),
            persistor: persistor
        )

        #expect(store.isAutosaveObservationActive == false)
        await store.restoreAsync(for: workspaceId)
        #expect(store.isAutosaveObservationActive == false)
        store.startObserving()
        #expect(store.isAutosaveObservationActive == true)
    }

    @Test
    func setBookmarkedEditor_nilClearsStoredBookmark() async {
        let atom = EditorChooserState()

        atom.setBookmarkedEditor("cursor")
        atom.setBookmarkedEditor(nil)

        #expect(atom.bookmarkedEditorId == nil)
    }
}
