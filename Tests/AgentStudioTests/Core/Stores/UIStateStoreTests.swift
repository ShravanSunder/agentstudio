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

        try uiStateStore.flush(for: workspaceId)

        let restoredAtom = UIStateAtom()
        let restoredStore = UIStateStore(atom: restoredAtom, persistor: persistor)
        restoredStore.restore(for: workspaceId)

        #expect(restoredAtom.expandedGroups == ["repo:agent-studio", "repo:askluna"])
        #expect(restoredAtom.checkoutColors == ["repo:agent-studio": "#ff6600"])
        #expect(restoredAtom.filterText == "terminal")
        #expect(restoredAtom.isFilterVisible)
    }
}
