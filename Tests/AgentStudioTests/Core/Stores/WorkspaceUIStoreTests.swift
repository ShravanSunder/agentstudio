import Foundation
import Observation
import Testing

@testable import AgentStudio

private final class ObservationInvalidationCounter: @unchecked Sendable {
    var didInvalidate = false
}

@Suite(.serialized)
@MainActor
final class WorkspaceSidebarStateStoreTests {
    @Test
    func filterState_settersUpdateFields() {
        let store = WorkspaceSidebarState()

        store.setFilterText("forge")
        store.setFilterVisible(true)

        #expect(store.filterText == "forge")
        #expect(store.isFilterVisible)
    }

    @Test
    func editorChooserState_mutatorsUpdateFields() {
        let preferenceAtom = EditorPreferenceAtom()
        let runtimeAtom = EditorChooserRuntimeAtom()
        let store = EditorChooserState(
            preferenceAtom: preferenceAtom,
            runtimeAtom: runtimeAtom
        )
        let paneId = UUID()

        store.setBookmarkedEditor("cursor")
        store.setOpenEditorPane(paneId)

        #expect(preferenceAtom.bookmarkedEditorId == "cursor")
        #expect(runtimeAtom.openForPaneId == paneId)
        #expect(store.bookmarkedEditorId == "cursor")
        #expect(store.openForPaneId == paneId)
    }

    @Test
    func editorChooserBookmarkedEditorReadIgnoresRuntimeOnlyChanges() {
        let preferenceAtom = EditorPreferenceAtom()
        let runtimeAtom = EditorChooserRuntimeAtom()
        let store = EditorChooserState(
            preferenceAtom: preferenceAtom,
            runtimeAtom: runtimeAtom
        )
        let invalidationCounter = ObservationInvalidationCounter()

        withObservationTracking {
            _ = store.bookmarkedEditorId
        } onChange: {
            invalidationCounter.didInvalidate = true
        }

        runtimeAtom.setOpenEditorPane(UUID())
        runtimeAtom.setAvailableTargets(ExternalEditorTarget.curatedOrder)

        #expect(!invalidationCounter.didInvalidate)
    }

    @Test
    func clear_resetsEditorChooserState() {
        let preferenceAtom = EditorPreferenceAtom()
        let runtimeAtom = EditorChooserRuntimeAtom()
        let store = EditorChooserState(
            preferenceAtom: preferenceAtom,
            runtimeAtom: runtimeAtom
        )

        store.setBookmarkedEditor("cursor")
        store.setOpenEditorPane(UUID())

        store.clear()

        #expect(preferenceAtom.bookmarkedEditorId == nil)
        #expect(runtimeAtom.openForPaneId == nil)
        #expect(store.bookmarkedEditorId == nil)
        #expect(store.openForPaneId == nil)
    }
}
