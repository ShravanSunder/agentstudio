import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class PaneArrangementInvariantTests {
    private var store: WorkspaceStore!

    init() {
        store = WorkspaceStore()
    }

    @Test
    func insertPaneAddsPaneToEveryArrangementInTab() throws {
        let firstPane = store.createPane()
        let tab = Tab(paneId: firstPane.id)
        store.appendTab(tab)
        let secondPane = store.createPane()
        store.insertPane(
            secondPane.id,
            inTab: tab.id,
            at: firstPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        let customArrangementId = try #require(store.createArrangement(name: "Focus", inTab: tab.id))

        let thirdPane = store.createPane()
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
        let parentPane = store.createPane()
        let tab = Tab(paneId: parentPane.id)
        store.appendTab(tab)
        let siblingPane = store.createPane()
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
        let parentPane = store.createPane()
        let tab = Tab(paneId: parentPane.id)
        store.appendTab(tab)
        let drawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let drawerId = try #require(store.pane(parentPane.id)?.drawer?.drawerId)

        store.removeDrawerPane(drawerPane.id, from: parentPane.id)

        let reconstitutedDrawerId = try #require(store.pane(parentPane.id)?.drawer?.drawerId)
        #expect(reconstitutedDrawerId == drawerId)
    }
}
