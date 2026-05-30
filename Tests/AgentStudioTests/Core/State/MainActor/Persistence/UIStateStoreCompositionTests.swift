import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct UIStateStoreCompositionTests {
    @Test("sidebar composition state round-trips and sidebarHasFocus remains runtime-only")
    func sidebarCompositionRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "ui-state-store-composition-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()

        let workspaceId = UUID()
        let atom = WorkspaceSidebarState()
        atom.setSidebarCollapsed(true)
        atom.setSidebarSurface(.inbox)
        atom.setSidebarHasFocus(true)

        try UIStateStore(atom: atom, editorChooserAtom: EditorChooserAtom(), persistor: persistor)
            .flush(for: workspaceId)

        let restoredAtom = WorkspaceSidebarState()
        UIStateStore(atom: restoredAtom, editorChooserAtom: EditorChooserAtom(), persistor: persistor)
            .restore(for: workspaceId)

        #expect(restoredAtom.sidebarCollapsed == true)
        #expect(restoredAtom.sidebarSurface == .inbox)
        #expect(restoredAtom.sidebarHasFocus == false)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("sidebar composition changes autosave after restore")
    func sidebarCompositionAutosavesAfterRestore() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "ui-state-store-composition-autosave-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()

        let workspaceId = UUID()
        let atom = WorkspaceSidebarState()
        let store = UIStateStore(
            atom: atom,
            editorChooserAtom: EditorChooserAtom(),
            persistor: persistor,
            persistDebounceDuration: .zero
        )
        store.restore(for: workspaceId)
        store.startObserving()

        atom.setSidebarCollapsed(true)
        atom.setSidebarSurface(.inbox)

        await assertEventuallyMain("sidebar composition should autosave") {
            switch persistor.loadUI(for: workspaceId) {
            case .loaded(let state):
                return state.sidebarCollapsed == true && state.sidebarSurface == .inbox
            case .missing, .corrupt:
                return false
            }
        }

        try? FileManager.default.removeItem(at: tempDir)
    }
}
