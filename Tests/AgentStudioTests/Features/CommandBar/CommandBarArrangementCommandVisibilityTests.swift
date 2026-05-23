import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct CommandBarArrangementCommandVisibilityTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private let dispatcher = CommandDispatcher.shared

    @Test
    func commandsScope_hidesCycleArrangementWhenOnlyDefaultArrangementExists() {
        let store = WorkspaceStore()
        let pane = store.createPane(source: .floating(launchDirectory: nil, title: "Solo"))
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
    func commandsScope_showsCycleArrangementWhenTabHasSavedArrangement() {
        let store = WorkspaceStore()
        let pane = store.createPane(source: .floating(launchDirectory: nil, title: "Primary"))
        var tab = Tab(paneId: pane.id)
        let savedArrangement = PaneArrangement(
            name: "Review",
            isDefault: false,
            layout: tab.layout,
            activePaneId: tab.activePaneId.map(MainPaneId.init)
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

        #expect(ids.contains("cmd-cycleArrangement"))
    }
}
