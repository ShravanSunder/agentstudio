import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
final class UIStateAtomTests {

    @Test
    func groupExpansion_updatesExpandedSet() {
        let store = UIStateAtom()

        store.setGroupExpanded("askluna", isExpanded: true)
        store.setGroupExpanded("personal", isExpanded: true)
        store.setGroupExpanded("personal", isExpanded: false)

        #expect(store.expandedGroups.contains("askluna"))
        #expect(!store.expandedGroups.contains("personal"))
    }

    @Test
    func checkoutColor_setAndClear() {
        let store = UIStateAtom()

        store.setCheckoutColor("#22cc88", for: "repoKey")
        #expect(store.checkoutColors["repoKey"] == "#22cc88")

        store.setCheckoutColor(nil, for: "repoKey")
        #expect(store.checkoutColors["repoKey"] == nil)
    }

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
        let store = UIStateAtom()
        let paneId = UUID()

        store.setBookmarkedEditor("cursor")
        store.setOpenEditorPane(paneId)

        #expect(store.editorChooserState.bookmarkedEditorId == "cursor")
        #expect(store.editorChooserState.openForPaneId == paneId)
    }

    @Test
    func clear_resetsEditorChooserState() {
        let store = UIStateAtom()

        store.setBookmarkedEditor("cursor")
        store.setOpenEditorPane(UUID())

        store.clear()

        #expect(store.editorChooserState.bookmarkedEditorId == nil)
        #expect(store.editorChooserState.openForPaneId == nil)
    }
}
