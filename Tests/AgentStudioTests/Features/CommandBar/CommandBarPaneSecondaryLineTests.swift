import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct CommandBarPaneSecondaryLineTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test
    func panesScopePaneNoteProvidesSecondaryLineOnlyWhenPresent() {
        let store = WorkspaceStore()
        let dispatcher = CommandDispatcher.shared
        let notedPane = store.createPane(source: .floating(launchDirectory: nil, title: "Terminal"))
        store.paneAtom.updatePaneNote(notedPane.id, note: "hiii")
        let plainPane = store.createPane(source: .floating(launchDirectory: nil, title: "Plain"))
        let tab = Tab(paneId: notedPane.id)
        store.appendTab(tab)
        store.insertPane(
            plainPane.id,
            inTab: tab.id,
            at: notedPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )

        let items = CommandBarDataSource.items(
            scope: .panes,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: dispatcher
        )
        let notedItem = items.first { $0.id == "pane-\(notedPane.id.uuidString)" }
        let plainItem = items.first { $0.id == "pane-\(plainPane.id.uuidString)" }

        #expect(
            notedItem?.secondaryLine
                == CommandBarItemSecondaryLine(
                    text: "hiii",
                    icon: .system(.longTextPageAndPencil)
                ))
        #expect(plainItem?.secondaryLine == nil)
    }
}
