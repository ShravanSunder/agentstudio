import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
final class WorkspaceUIStoreTests {

    @Test
    func groupExpansion_updatesExpandedSet() {
        let store = WorkspaceUIStore()

        store.setGroupExpanded("askluna", isExpanded: true)
        store.setGroupExpanded("personal", isExpanded: true)
        store.setGroupExpanded("personal", isExpanded: false)

        #expect(store.expandedGroups.contains("askluna"))
        #expect(!store.expandedGroups.contains("personal"))
    }

    @Test
    func checkoutColor_setAndClear() {
        let store = WorkspaceUIStore()

        store.setCheckoutColor("#22cc88", for: "repoKey")
        #expect(store.checkoutColors["repoKey"] == "#22cc88")

        store.setCheckoutColor(nil, for: "repoKey")
        #expect(store.checkoutColors["repoKey"] == nil)
    }

    @Test
    func filterState_settersUpdateFields() {
        let store = WorkspaceUIStore()

        store.setFilterText("forge")
        store.setFilterVisible(true)

        #expect(store.filterText == "forge")
        #expect(store.isFilterVisible)
    }
}
