import Foundation
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
    func flushAndRestore_roundTripsPersistedUIState() throws {
        let workspaceId = UUID()
        let atom = WorkspaceSidebarState()
        let uiStateStore = UIStateStore(atom: atom, editorChooserState: EditorChooserState(), persistor: persistor)

        atom.setFilterText("terminal")
        atom.setFilterVisible(true)
        atom.setSidebarCollapsed(true)
        atom.setSidebarSurface(.inbox)
        atom.setSidebarHasFocus(true)

        try uiStateStore.flush(for: workspaceId)

        let restoredAtom = WorkspaceSidebarState()
        let restoredStore = UIStateStore(
            atom: restoredAtom,
            editorChooserState: EditorChooserState(),
            persistor: persistor
        )
        restoredStore.restore(for: workspaceId)

        #expect(restoredAtom.filterText == "terminal")
        #expect(restoredAtom.isFilterVisible)
        #expect(restoredAtom.sidebarCollapsed)
        #expect(restoredAtom.sidebarSurface == .inbox)
        #expect(restoredAtom.sidebarHasFocus == false)
    }

    @Test
    func flush_operatesOnTheProvidedLiveAtomScope() throws {
        let workspaceId = UUID()
        let atom = WorkspaceSidebarState()
        let store = UIStateStore(atom: atom, editorChooserState: EditorChooserState(), persistor: persistor)

        atom.setFilterText("agent")
        atom.setFilterVisible(true)
        atom.setSidebarCollapsed(true)
        atom.setSidebarSurface(.inbox)
        atom.setSidebarHasFocus(true)

        try store.flush(for: workspaceId)

        let restoredAtom = WorkspaceSidebarState()
        UIStateStore(
            atom: restoredAtom,
            editorChooserState: EditorChooserState(),
            persistor: persistor
        ).restore(for: workspaceId)

        #expect(restoredAtom.filterText == "agent")
        #expect(restoredAtom.isFilterVisible)
        #expect(restoredAtom.sidebarCollapsed)
        #expect(restoredAtom.sidebarSurface == .inbox)
        #expect(restoredAtom.sidebarHasFocus == false)
    }

    @Test
    func restore_corruptUIFile_fallsBackToDefaults() throws {
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

        store.restore(for: workspaceId)

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
    func flushFailure_reportsSaveFailedRecovery() {
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

        #expect(throws: Error.self) {
            try store.flush(for: workspaceId)
        }

        #expect(reportedRecovery?.store == .uiState)
        #expect(reportedRecovery?.workspaceId == workspaceId)
        #expect(reportedRecovery?.recovery == .saveFailed)
    }

    @Test
    func restore_legacyShowMinimizedBarsField_isIgnored() throws {
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

        store.restore(for: workspaceId)

        #expect(atom.sidebarCollapsed)
    }

    @Test
    func restore_missingSidebarCompositionFields_defaultsToCollapsedFalseAndReposSurface() throws {
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
        UIStateStore(
            atom: atom,
            editorChooserState: EditorChooserState(),
            persistor: persistor
        ).restore(for: workspaceId)

        #expect(atom.sidebarCollapsed == false)
        #expect(atom.sidebarSurface == .repos)
        #expect(atom.sidebarHasFocus == false)
    }

    @Test
    func restore_corruptFilterFields_preservesOtherUIState() throws {
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
        UIStateStore(
            atom: atom,
            editorChooserState: EditorChooserState(),
            persistor: persistor
        ).restore(for: workspaceId)

        #expect(atom.filterText.isEmpty)
        #expect(atom.isFilterVisible == false)
        #expect(atom.sidebarCollapsed)
        #expect(atom.sidebarSurface == .inbox)
    }

    @Test
    func editorChooserState_roundTripsThroughUIStatePersistence() throws {
        let workspaceId = UUID()
        let atom = WorkspaceSidebarState()
        let editorChooser = EditorChooserState()
        let store = UIStateStore(atom: atom, editorChooserState: editorChooser, persistor: persistor)

        editorChooser.setBookmarkedEditor("cursor")
        editorChooser.setOpenEditorPane(UUID())

        try store.flush(for: workspaceId)
        let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        let persistedPayload = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: uiURL)) as? [String: Any]
        )
        let persistedEditorChooserState = try #require(
            persistedPayload["editorChooserState"] as? [String: Any]
        )
        #expect(persistedEditorChooserState["bookmarkedEditorId"] as? String == "cursor")
        #expect(persistedEditorChooserState["openForPaneId"] == nil)

        let restoredAtom = WorkspaceSidebarState()
        let restoredEditorChooser = EditorChooserState()
        UIStateStore(
            atom: restoredAtom,
            editorChooserState: restoredEditorChooser,
            persistor: persistor
        ).restore(for: workspaceId)

        #expect(restoredEditorChooser.bookmarkedEditorId == "cursor")
        #expect(restoredEditorChooser.openForPaneId == nil)
    }

    @Test
    func directEditorPreferenceMutation_autosavesThroughComposedState() async throws {
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
        store.restore(for: workspaceId)
        store.startObserving()

        preferenceAtom.setBookmarkedEditor("cursor")

        await assertEventuallyMain("editor preference write-owner mutation should autosave") {
            switch persistor.loadUI(for: workspaceId) {
            case .loaded(let state):
                return state.editorChooserState.bookmarkedEditorId == "cursor"
            case .missing, .corrupt:
                return false
            }
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
        store.restore(for: workspaceId)
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
    func restore_missingEditorChooserState_defaultsToEmptyState() throws {
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
        UIStateStore(atom: atom, editorChooserState: editorChooser, persistor: persistor).restore(for: workspaceId)

        #expect(editorChooser.bookmarkedEditorId == nil)
        #expect(editorChooser.openForPaneId == nil)
    }

    @Test
    func restore_persistedOpenEditorPane_isResetToNil() throws {
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
        UIStateStore(atom: atom, editorChooserState: editorChooser, persistor: persistor).restore(for: workspaceId)

        #expect(editorChooser.bookmarkedEditorId == "cursor")
        #expect(editorChooser.openForPaneId == nil)
    }

    @Test
    func restore_corruptEditorChooserState_preservesOtherUIState() throws {
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
        UIStateStore(atom: atom, editorChooserState: editorChooser, persistor: persistor).restore(for: workspaceId)

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

        store.restore(for: workspaceAId)
        store.startObserving()
        atom.setFilterText("workspace-a-draft")
        await clock.waitForPendingSleepCount()
        store.restore(for: workspaceBId)
        clock.advance(by: .milliseconds(10))
        await Task.yield()

        guard case .missing = persistor.loadUI(for: workspaceAId) else {
            Issue.record("Expected stale workspace A debounce to be cancelled")
            return
        }
    }

    @Test
    func autosaveObservationStateIsExplicitlyArmed() {
        let workspaceId = UUID()
        let store = UIStateStore(
            atom: WorkspaceSidebarState(),
            editorChooserState: EditorChooserState(),
            persistor: persistor
        )

        #expect(store.isAutosaveObservationActive == false)
        store.restore(for: workspaceId)
        #expect(store.isAutosaveObservationActive == false)
        store.startObserving()
        #expect(store.isAutosaveObservationActive == true)
    }

    @Test
    func setBookmarkedEditor_nilClearsStoredBookmark() {
        let atom = EditorChooserState()

        atom.setBookmarkedEditor("cursor")
        atom.setBookmarkedEditor(nil)

        #expect(atom.bookmarkedEditorId == nil)
    }
}
