import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite(.serialized)
final class PaneArrangementInvariantTests {
    private var store: WorkspaceStore!

    init() {
        store = WorkspaceStore()
    }

    @Test
    func genericInsertPaneFromDefaultPlacesExistingIdentityInEveryArrangement() throws {
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
        let firstCustomArrangementID = try #require(store.createArrangement(name: "First", inTab: tab.id))
        let secondCustomArrangementID = try #require(store.createArrangement(name: "Second", inTab: tab.id))
        store.switchArrangement(to: tab.defaultArrangement.id, inTab: tab.id)
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
        #expect(updatedTab.defaultArrangement.layout.contains(thirdPane.id))
        #expect(
            updatedTab.arrangements.first { $0.id == firstCustomArrangementID }?.layout.contains(thirdPane.id) == true)
        #expect(
            updatedTab.arrangements.first { $0.id == secondCustomArrangementID }?.layout.contains(thirdPane.id) == true)
        #expect(updatedTab.allPaneIds.filter { $0 == thirdPane.id }.count == 1)
    }

    @Test
    func genericInsertPaneFromCustomPlacesExistingIdentityInEveryArrangement() throws {
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
        let untouchedArrangementID = try #require(store.createArrangement(name: "Untouched", inTab: tab.id))
        let activeArrangementID = try #require(store.createArrangement(name: "Active", inTab: tab.id))
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
        #expect(updatedTab.defaultArrangement.layout.contains(thirdPane.id))
        #expect(updatedTab.arrangements.first { $0.id == activeArrangementID }?.layout.contains(thirdPane.id) == true)
        #expect(
            updatedTab.arrangements.first { $0.id == untouchedArrangementID }?.layout.contains(thirdPane.id) == true)
        #expect(updatedTab.allPaneIds.filter { $0 == thirdPane.id }.count == 1)
    }

    @Test
    func genericInsertDrawerPaneFromDefaultPlacesExistingIdentityInEveryArrangement() throws {
        let parentPane = store.createPane()
        let tab = Tab(paneId: parentPane.id)
        store.appendTab(tab)
        _ = try #require(store.addDrawerPane(to: parentPane.id))
        _ = try #require(store.createArrangement(name: "First", inTab: tab.id))
        _ = try #require(store.createArrangement(name: "Second", inTab: tab.id))
        store.switchArrangement(to: tab.defaultArrangement.id, inTab: tab.id)
        let insertedDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))

        let updatedTab = try #require(store.tab(tab.id))
        let drawerID = try #require(store.pane(parentPane.id)?.drawer?.drawerId)
        #expect(updatedTab.defaultArrangement.drawerViews[drawerID]?.layout.contains(insertedDrawerPane.id) == true)
        #expect(
            updatedTab.arrangements
                .filter { !$0.isDefault }
                .allSatisfy { $0.drawerViews[drawerID]?.layout.contains(insertedDrawerPane.id) == true }
        )
        #expect(updatedTab.allPaneIds.filter { $0 == insertedDrawerPane.id }.count == 1)
    }

    @Test
    func genericInsertDrawerPaneFromCustomPlacesExistingIdentityInEveryArrangement() throws {
        let parentPane = store.createPane()
        let tab = Tab(paneId: parentPane.id)
        store.appendTab(tab)
        _ = try #require(store.addDrawerPane(to: parentPane.id))
        let untouchedArrangementID = try #require(store.createArrangement(name: "Untouched", inTab: tab.id))
        let activeArrangementID = try #require(store.createArrangement(name: "Active", inTab: tab.id))
        let insertedDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))

        let updatedTab = try #require(store.tab(tab.id))
        let drawerID = try #require(store.pane(parentPane.id)?.drawer?.drawerId)
        #expect(updatedTab.defaultArrangement.drawerViews[drawerID]?.layout.contains(insertedDrawerPane.id) == true)
        #expect(
            updatedTab.arrangements.first { $0.id == activeArrangementID }?
                .drawerViews[drawerID]?.layout.contains(insertedDrawerPane.id) == true
        )
        #expect(
            updatedTab.arrangements.first { $0.id == untouchedArrangementID }?
                .drawerViews[drawerID]?.layout.contains(insertedDrawerPane.id) == true
        )
        #expect(updatedTab.allPaneIds.filter { $0 == insertedDrawerPane.id }.count == 1)
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
