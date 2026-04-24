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
        let uiStateStore = UIStateStore(atom: atom, persistor: persistor)

        atom.setExpandedGroups(["repo:agent-studio", "repo:askluna"])
        atom.setCheckoutColor("#ff6600", for: "repo:agent-studio")
        atom.setFilterText("terminal")
        atom.setFilterVisible(true)
        atom.setShowMinimizedBars(false)

        try uiStateStore.flush(for: workspaceId)

        let restoredAtom = UIStateAtom()
        let restoredStore = UIStateStore(atom: restoredAtom, persistor: persistor)
        restoredStore.restore(for: workspaceId)

        #expect(restoredAtom.expandedGroups == ["repo:agent-studio", "repo:askluna"])
        #expect(restoredAtom.checkoutColors == ["repo:agent-studio": "#ff6600"])
        #expect(restoredAtom.filterText == "terminal")
        #expect(restoredAtom.isFilterVisible)
        #expect(restoredAtom.showMinimizedBars == false)
    }

    @Test
    func flush_operatesOnTheProvidedLiveAtomScope() throws {
        let workspaceId = UUID()
        let atom = UIStateAtom()
        let store = UIStateStore(atom: atom, persistor: persistor)

        atom.setFilterText("agent")
        atom.setFilterVisible(true)
        atom.setShowMinimizedBars(false)

        try store.flush(for: workspaceId)

        let restoredAtom = UIStateAtom()
        UIStateStore(atom: restoredAtom, persistor: persistor).restore(for: workspaceId)

        #expect(restoredAtom.filterText == "agent")
        #expect(restoredAtom.isFilterVisible)
        #expect(restoredAtom.showMinimizedBars == false)
    }

    @Test
    func restore_corruptUIFile_fallsBackToDefaults() throws {
        let workspaceId = UUID()
        let corruptURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        try "not json".write(to: corruptURL, atomically: true, encoding: .utf8)

        let atom = UIStateAtom()
        let store = UIStateStore(atom: atom, persistor: persistor)

        store.restore(for: workspaceId)

        #expect(atom.expandedGroups.isEmpty)
        #expect(atom.checkoutColors.isEmpty)
        #expect(atom.filterText.isEmpty)
        #expect(!atom.isFilterVisible)
        #expect(atom.showMinimizedBars)
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
                "expandedGroups": [],
                "checkoutColors": {},
                "filterText": "",
                "isFilterVisible": false
            }
            """
        let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        try Data(json.utf8).write(to: uiURL, options: .atomic)

        let atom = UIStateAtom()
        let store = UIStateStore(atom: atom, persistor: persistor)

        store.restore(for: workspaceId)

        #expect(atom.showMinimizedBars)
    }

    @Test
    func editorChooserState_roundTripsThroughUIStatePersistence() throws {
        let workspaceId = UUID()
        let atom = UIStateAtom()
        let store = UIStateStore(atom: atom, persistor: persistor)

        atom.setBookmarkedEditor("cursor")
        atom.setOpenEditorPane(UUID())

        try store.flush(for: workspaceId)

        let restoredAtom = UIStateAtom()
        UIStateStore(atom: restoredAtom, persistor: persistor).restore(for: workspaceId)

        #expect(restoredAtom.editorChooserState.bookmarkedEditorId == "cursor")
        #expect(restoredAtom.editorChooserState.openForPaneId == nil)
    }

    @Test
    func restore_missingEditorChooserState_defaultsToEmptyState() throws {
        let workspaceId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "workspaceId": "\(workspaceId.uuidString)",
                "expandedGroups": [],
                "checkoutColors": {},
                "filterText": "",
                "isFilterVisible": false,
                "showMinimizedBars": true
            }
            """
        let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        try Data(json.utf8).write(to: uiURL, options: .atomic)

        let atom = UIStateAtom()
        UIStateStore(atom: atom, persistor: persistor).restore(for: workspaceId)

        #expect(atom.editorChooserState.bookmarkedEditorId == nil)
        #expect(atom.editorChooserState.openForPaneId == nil)
    }

    @Test
    func restore_persistedOpenEditorPane_isResetToNil() throws {
        let workspaceId = UUID()
        let persistedPaneId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "workspaceId": "\(workspaceId.uuidString)",
                "expandedGroups": [],
                "checkoutColors": {},
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
        UIStateStore(atom: atom, persistor: persistor).restore(for: workspaceId)

        #expect(atom.editorChooserState.bookmarkedEditorId == "cursor")
        #expect(atom.editorChooserState.openForPaneId == nil)
    }

    @Test
    func restore_corruptEditorChooserState_preservesOtherUIState() throws {
        let workspaceId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "workspaceId": "\(workspaceId.uuidString)",
                "expandedGroups": ["repo:agent-studio"],
                "checkoutColors": {"repo:agent-studio": "#ff6600"},
                "filterText": "terminal",
                "isFilterVisible": true,
                "showMinimizedBars": false,
                "editorChooserState": "bad-value"
            }
            """
        let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        try Data(json.utf8).write(to: uiURL, options: .atomic)

        let atom = UIStateAtom()
        UIStateStore(atom: atom, persistor: persistor).restore(for: workspaceId)

        #expect(atom.expandedGroups == ["repo:agent-studio"])
        #expect(atom.checkoutColors == ["repo:agent-studio": "#ff6600"])
        #expect(atom.filterText == "terminal")
        #expect(atom.isFilterVisible)
        #expect(atom.showMinimizedBars == false)
        #expect(atom.editorChooserState.bookmarkedEditorId == nil)
        #expect(atom.editorChooserState.openForPaneId == nil)
    }

    @Test
    func setBookmarkedEditor_nilClearsStoredBookmark() {
        let atom = UIStateAtom()

        atom.setBookmarkedEditor("cursor")
        atom.setBookmarkedEditor(nil)

        #expect(atom.editorChooserState.bookmarkedEditorId == nil)
    }
}
