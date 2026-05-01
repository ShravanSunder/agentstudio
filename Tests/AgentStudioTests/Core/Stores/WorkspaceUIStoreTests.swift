import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
final class UIStateAtomTests {
    @Test
    func filterState_settersUpdateFields() {
        let store = UIStateAtom()

        store.setFilterText("forge")
        store.setFilterVisible(true)

        #expect(store.filterText == "forge")
        #expect(store.isFilterVisible)
    }

    @Test
    func editorChooserState_mutatorsUpdateFields() {
        let store = EditorChooserAtom()
        let paneId = UUID()

        store.setBookmarkedEditor("cursor")
        store.setOpenEditorPane(paneId)

        #expect(store.state.bookmarkedEditorId == "cursor")
        #expect(store.state.openForPaneId == paneId)
    }

    @Test
    func clear_resetsEditorChooserState() {
        let store = EditorChooserAtom()

        store.setBookmarkedEditor("cursor")
        store.setOpenEditorPane(UUID())

        store.clear()

        #expect(store.state.bookmarkedEditorId == nil)
        #expect(store.state.openForPaneId == nil)
    }
}
