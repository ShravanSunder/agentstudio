import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class PaneArrangementInvariantTests {
    private var store: WorkspaceStore!

    init() {
        store = WorkspaceStore(
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)))
    }

    @Test
    func insertPaneAddsPaneToEveryArrangementInTab() throws {
        let firstPane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
        let tab = Tab(paneId: firstPane.id)
        store.appendTab(tab)
        let secondPane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
        store.insertPane(
            secondPane.id,
            inTab: tab.id,
            at: firstPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        let customArrangementId = try #require(store.createArrangement(name: "Focus", inTab: tab.id))

        let thirdPane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
        store.insertPane(
            thirdPane.id,
            inTab: tab.id,
            at: firstPane.id,
            direction: .vertical,
            position: .after,
            sizingMode: .halveTarget
        )

        let updatedTab = try #require(store.tab(tab.id))
        let customArrangement = try #require(updatedTab.arrangements.first { $0.id == customArrangementId })
        #expect(updatedTab.arrangements.allSatisfy { Set($0.layout.paneIds) == Set(updatedTab.allPaneIds) })
        #expect(customArrangement.layout.contains(thirdPane.id))
    }

    @Test
    func removePanePrunesOwnedDrawerViews() throws {
        let parentPane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
        let tab = Tab(paneId: parentPane.id)
        store.appendTab(tab)
        let siblingPane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
        store.insertPane(
            siblingPane.id,
            inTab: tab.id,
            at: parentPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        let drawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let drawerId = try #require(store.pane(parentPane.id)?.drawer?.drawerId)
        _ = try #require(store.createArrangement(name: "Focus", inTab: tab.id))

        store.removePane(parentPane.id)

        let updatedTab = try #require(store.tab(tab.id))
        #expect(store.pane(drawerPane.id) == nil)
        #expect(updatedTab.arrangements.allSatisfy { $0.drawerViews[drawerId] == nil })
    }

    @Test
    func removingLastDrawerPanePreservesDrawerIdentity() throws {
        let parentPane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
        let tab = Tab(paneId: parentPane.id)
        store.appendTab(tab)
        let drawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let drawerId = try #require(store.pane(parentPane.id)?.drawer?.drawerId)

        store.removeDrawerPane(drawerPane.id, from: parentPane.id)

        let reconstitutedDrawerId = try #require(store.pane(parentPane.id)?.drawer?.drawerId)
        #expect(reconstitutedDrawerId == drawerId)
    }

    @Test
    func addDrawerPaneView_fansOutToEveryArrangementContainingParent() throws {
        let parentPane = UUID()
        let drawerPane = UUID()
        let drawerId = UUID()
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: parentPane),
            activePaneId: MainPaneId(parentPane)
        )
        let layoutOne = PaneArrangement(
            name: "Layout 1",
            isDefault: false,
            layout: Layout(paneId: parentPane),
            activePaneId: MainPaneId(parentPane)
        )
        let layoutTwo = PaneArrangement(
            name: "Layout 2",
            isDefault: false,
            layout: Layout(paneId: parentPane),
            activePaneId: MainPaneId(parentPane)
        )
        let atom = WorkspaceTabArrangementAtom()
        let tabId = UUID()
        atom.appendState(
            TabArrangementState(
                tabId: tabId,
                allPaneIds: [parentPane, drawerPane],
                arrangements: [defaultArrangement, layoutOne, layoutTwo],
                activeArrangementId: defaultArrangement.id,
                zoomedPaneId: nil
            )
        )

        atom.addDrawerPaneView(
            drawerId: drawerId,
            parentPaneId: parentPane,
            drawerPaneId: drawerPane,
            inTab: tabId
        )

        let state = try #require(atom.arrangementState(tabId))
        #expect(state.arrangements.allSatisfy { $0.drawerViews[drawerId]?.layout.paneIds == [drawerPane] })
    }
}
