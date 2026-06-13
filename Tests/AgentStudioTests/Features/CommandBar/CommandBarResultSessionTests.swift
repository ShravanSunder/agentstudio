import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct CommandBarResultSessionTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("result session owns item filtering, grouping, and selection")
    func resultSessionOwnsFilteringGroupingAndSelection() {
        let store = WorkspaceStore()
        let repoCache = RepoCacheAtom()
        let state = CommandBarState()
        state.show(prefix: ">")
        state.rawInput = "> close"

        let session = CommandBarResultSession(
            store: store,
            repoCache: repoCache,
            dispatcher: .shared
        )

        let snapshot = session.snapshot(state: state)

        #expect(
            snapshot.filteredItems.allSatisfy { item in
                item.title.localizedCaseInsensitiveContains("close")
                    || item.keywords.contains { $0.localizedCaseInsensitiveContains("close") }
            })
        #expect(
            snapshot.displayedItems.map(\.id)
                == CommandBarDataSource.displayItems(from: snapshot.groups).map(\.id)
        )
        #expect(snapshot.selectedItem?.id == snapshot.displayedItems.first?.id)
        #expect(snapshot.totalItems == snapshot.displayedItems.count)
    }

    @Test("nested result session uses level items instead of rebuilding root items")
    func nestedResultSessionUsesLevelItems() {
        let state = CommandBarState()
        let nestedItem = CommandBarItem(
            id: "nested-open",
            title: "Open Here",
            group: "Actions",
            groupPriority: 1,
            action: .custom({})
        )
        state.pushLevel(
            CommandBarLevel(
                id: "worktree-actions",
                title: "Worktree Actions",
                items: [nestedItem]
            )
        )

        let session = CommandBarResultSession(
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: .shared
        )

        let snapshot = session.snapshot(state: state)

        #expect(snapshot.allItems.map(\.id) == ["nested-open"])
        #expect(snapshot.selectedItem?.id == "nested-open")
    }
}
