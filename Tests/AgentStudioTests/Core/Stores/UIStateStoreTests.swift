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
        let atom = UIStateAtom()
        let uiStateStore = UIStateStore(atom: atom, editorChooserAtom: EditorChooserAtom(), persistor: persistor)

        atom.setFilterText("terminal")
        atom.setFilterVisible(true)
        atom.setShowMinimizedBars(false)
        atom.setSidebarCollapsed(true)
        atom.setSidebarSurface(.inbox)
        atom.setSidebarHasFocus(true)

        try uiStateStore.flush(for: workspaceId)

        let restoredAtom = UIStateAtom()
        let restoredStore = UIStateStore(
            atom: restoredAtom,
            editorChooserAtom: EditorChooserAtom(),
            persistor: persistor
        )
        restoredStore.restore(for: workspaceId)

        #expect(restoredAtom.filterText == "terminal")
        #expect(restoredAtom.isFilterVisible)
        #expect(restoredAtom.showMinimizedBars == false)
        #expect(restoredAtom.sidebarCollapsed)
        #expect(restoredAtom.sidebarSurface == .inbox)
        #expect(restoredAtom.sidebarHasFocus == false)
    }

    @Test
    func flush_operatesOnTheProvidedLiveAtomScope() throws {
        let workspaceId = UUID()
        let atom = UIStateAtom()
        let store = UIStateStore(atom: atom, editorChooserAtom: EditorChooserAtom(), persistor: persistor)

        atom.setFilterText("agent")
        atom.setFilterVisible(true)
        atom.setShowMinimizedBars(false)
        atom.setSidebarCollapsed(true)
        atom.setSidebarSurface(.inbox)
        atom.setSidebarHasFocus(true)

        try store.flush(for: workspaceId)

        let restoredAtom = UIStateAtom()
        UIStateStore(
            atom: restoredAtom,
            editorChooserAtom: EditorChooserAtom(),
            persistor: persistor
        ).restore(for: workspaceId)

        #expect(restoredAtom.filterText == "agent")
        #expect(restoredAtom.isFilterVisible)
        #expect(restoredAtom.showMinimizedBars == false)
        #expect(restoredAtom.sidebarCollapsed)
        #expect(restoredAtom.sidebarSurface == .inbox)
        #expect(restoredAtom.sidebarHasFocus == false)
    }

    @Test
    func restore_corruptUIFile_fallsBackToDefaults() throws {
        let workspaceId = UUID()
        let corruptURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        try "not json".write(to: corruptURL, atomically: true, encoding: .utf8)

        let atom = UIStateAtom()
        var reportedRecovery: PersistenceRecoveryEvent?
        let store = UIStateStore(
            atom: atom,
            editorChooserAtom: EditorChooserAtom(),
            persistor: persistor,
            recoveryReporter: { reportedRecovery = $0 }
        )

        store.restore(for: workspaceId)

        #expect(atom.filterText.isEmpty)
        #expect(!atom.isFilterVisible)
        #expect(atom.showMinimizedBars)
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
    func showMinimizedBars_defaultsToTrue() {
        let atom = UIStateAtom()

        #expect(atom.showMinimizedBars)
    }

    @Test
    func setShowMinimizedBars_updatesValue() {
        let atom = UIStateAtom()

        atom.setShowMinimizedBars(false)

        #expect(atom.showMinimizedBars == false)
    }

    @Test
    func restore_missingShowMinimizedBars_defaultsToTrue() throws {
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

        let atom = UIStateAtom()
        let store = UIStateStore(atom: atom, editorChooserAtom: EditorChooserAtom(), persistor: persistor)

        store.restore(for: workspaceId)

        #expect(atom.showMinimizedBars)
    }

    @Test
    func restore_missingSidebarCompositionFields_defaultsToCollapsedFalseAndReposSurface() throws {
        let workspaceId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "workspaceId": "\(workspaceId.uuidString)",
                "filterText": "",
                "isFilterVisible": false,
                "showMinimizedBars": true
            }
            """
        let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        try Data(json.utf8).write(to: uiURL, options: .atomic)

        let atom = UIStateAtom()
        UIStateStore(atom: atom, editorChooserAtom: EditorChooserAtom(), persistor: persistor).restore(for: workspaceId)

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

        let atom = UIStateAtom()
        UIStateStore(atom: atom, editorChooserAtom: EditorChooserAtom(), persistor: persistor).restore(for: workspaceId)

        #expect(atom.filterText.isEmpty)
        #expect(atom.isFilterVisible == false)
        #expect(atom.showMinimizedBars == false)
        #expect(atom.sidebarCollapsed)
        #expect(atom.sidebarSurface == .inbox)
    }

    @Test
    func editorChooserState_roundTripsThroughUIStatePersistence() throws {
        let workspaceId = UUID()
        let atom = UIStateAtom()
        let editorChooser = EditorChooserAtom()
        let store = UIStateStore(atom: atom, editorChooserAtom: editorChooser, persistor: persistor)

        editorChooser.setBookmarkedEditor("cursor")
        editorChooser.setOpenEditorPane(UUID())

        try store.flush(for: workspaceId)

        let restoredAtom = UIStateAtom()
        let restoredEditorChooser = EditorChooserAtom()
        UIStateStore(
            atom: restoredAtom,
            editorChooserAtom: restoredEditorChooser,
            persistor: persistor
        ).restore(for: workspaceId)

        #expect(restoredEditorChooser.state.bookmarkedEditorId == "cursor")
        #expect(restoredEditorChooser.state.openForPaneId == nil)
    }

    @Test
    func restore_missingEditorChooserState_defaultsToEmptyState() throws {
        let workspaceId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "workspaceId": "\(workspaceId.uuidString)",
                "filterText": "",
                "isFilterVisible": false,
                "showMinimizedBars": true
            }
            """
        let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        try Data(json.utf8).write(to: uiURL, options: .atomic)

        let atom = UIStateAtom()
        let editorChooser = EditorChooserAtom()
        UIStateStore(atom: atom, editorChooserAtom: editorChooser, persistor: persistor).restore(for: workspaceId)

        #expect(editorChooser.state.bookmarkedEditorId == nil)
        #expect(editorChooser.state.openForPaneId == nil)
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
                "showMinimizedBars": true,
                "editorChooserState": {
                    "openForPaneId": "\(persistedPaneId.uuidString)",
                    "bookmarkedEditorId": "cursor"
                }
            }
            """
        let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        try Data(json.utf8).write(to: uiURL, options: .atomic)

        let atom = UIStateAtom()
        let editorChooser = EditorChooserAtom()
        UIStateStore(atom: atom, editorChooserAtom: editorChooser, persistor: persistor).restore(for: workspaceId)

        #expect(editorChooser.state.bookmarkedEditorId == "cursor")
        #expect(editorChooser.state.openForPaneId == nil)
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
                "showMinimizedBars": false,
                "editorChooserState": "bad-value"
            }
            """
        let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        try Data(json.utf8).write(to: uiURL, options: .atomic)

        let atom = UIStateAtom()
        let editorChooser = EditorChooserAtom()
        UIStateStore(atom: atom, editorChooserAtom: editorChooser, persistor: persistor).restore(for: workspaceId)

        #expect(atom.filterText == "terminal")
        #expect(atom.isFilterVisible)
        #expect(atom.showMinimizedBars == false)
        #expect(editorChooser.state.bookmarkedEditorId == nil)
        #expect(editorChooser.state.openForPaneId == nil)
    }

    @Test
    func setBookmarkedEditor_nilClearsStoredBookmark() {
        let atom = EditorChooserAtom()

        atom.setBookmarkedEditor("cursor")
        atom.setBookmarkedEditor(nil)

        #expect(atom.state.bookmarkedEditorId == nil)
    }
}
