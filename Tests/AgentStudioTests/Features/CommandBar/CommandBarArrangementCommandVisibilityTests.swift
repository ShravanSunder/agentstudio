import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct CommandBarArrangementCommandVisibilityTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private let dispatcher = AppCommandDispatcher.shared

    @Test
    func commandsScope_hidesCycleArrangementWhenOnlyDefaultArrangementExists() {
        let store = WorkspaceStore()
        let pane = store.createPane()
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let items = CommandBarDataSource.items(
            scope: .commands,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: dispatcher
        )
        let ids = Set(items.map(\.id))

        #expect(!ids.contains("cmd-cycleArrangement"))
    }

    @Test
    func commandsScope_showsArrangementCommandsWhenTabHasSavedArrangement() {
        let store = WorkspaceStore()
        let pane = store.createPane()
        var tab = Tab(paneId: pane.id)
        let savedArrangement = PaneArrangement(
            name: "Review",
            isDefault: false,
            layout: tab.layout,
            activePaneId: tab.activePaneId
        )
        tab.arrangements.append(savedArrangement)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let items = CommandBarDataSource.items(
            scope: .commands,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: dispatcher
        )
        let ids = Set(items.map(\.id))

        #expect(ids.contains("cmd-switchArrangement"))
        #expect(ids.contains("cmd-previousArrangement"))
        #expect(ids.contains("cmd-nextArrangement"))
        #expect(!ids.contains("cmd-cycleArrangement"))
    }
}
