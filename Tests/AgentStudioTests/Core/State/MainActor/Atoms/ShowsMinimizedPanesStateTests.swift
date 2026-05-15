import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Shows minimized panes state")
struct ShowsMinimizedPanesStateTests {
    @Test
    func setShowsMinimizedPanes_mutatesOnlyActiveArrangement() throws {
        let paneA = UUID()
        let paneB = UUID()
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout.autoTiled([paneA, paneB]),
            showsMinimizedPanes: true,
            activePaneId: paneA
        )
        let customArrangement = PaneArrangement(
            name: "Focus",
            isDefault: false,
            layout: Layout(paneId: paneA),
            showsMinimizedPanes: true,
            activePaneId: paneA
        )
        let tab = Tab(
            allPaneIds: [paneA, paneB],
            arrangements: [defaultArrangement, customArrangement],
            activeArrangementId: customArrangement.id
        )
        let tabLayout = WorkspaceTabLayoutAtom()
        tabLayout.appendTab(tab)

        tabLayout.setShowsMinimizedPanes(false, inTab: tab.id)

        let updatedTab = try #require(tabLayout.tab(tab.id))
        let updatedDefault = try #require(updatedTab.arrangements.first { $0.id == defaultArrangement.id })
        let updatedCustom = try #require(updatedTab.arrangements.first { $0.id == customArrangement.id })
        #expect(updatedDefault.showsMinimizedPanes == true)
        #expect(updatedCustom.showsMinimizedPanes == false)
    }

    @Test
    func setShowsMinimizedDrawerPanes_mutatesOnlyActiveArrangementDrawerView() throws {
        let parentPaneId = UUID()
        let drawerId = UUID()
        let drawerPaneId = UUID()
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: parentPaneId),
            activePaneId: parentPaneId,
            drawerViews: [
                drawerId: DrawerView(
                    layout: DrawerGridLayout(topRow: Layout(paneId: drawerPaneId)),
                    showsMinimizedPanes: true
                )
            ]
        )
        let customArrangement = PaneArrangement(
            name: "Focus",
            isDefault: false,
            layout: Layout(paneId: parentPaneId),
            activePaneId: parentPaneId,
            drawerViews: [
                drawerId: DrawerView(
                    layout: DrawerGridLayout(topRow: Layout(paneId: drawerPaneId)),
                    showsMinimizedPanes: true
                )
            ]
        )
        let tab = Tab(
            allPaneIds: [parentPaneId],
            arrangements: [defaultArrangement, customArrangement],
            activeArrangementId: customArrangement.id
        )
        let tabArrangement = WorkspaceTabArrangementAtom()
        tabArrangement.appendState(
            TabArrangementState(
                tabId: tab.id,
                allPaneIds: tab.allPaneIds,
                arrangements: tab.arrangements,
                activeArrangementId: tab.activeArrangementId,
                zoomedPaneId: tab.zoomedPaneId
            )
        )

        tabArrangement.setShowsMinimizedDrawerPanes(false, drawerId: drawerId, inTab: tab.id)

        let updatedState = try #require(tabArrangement.arrangementState(tab.id))
        let updatedDefault = try #require(updatedState.arrangements.first { $0.id == defaultArrangement.id })
        let updatedCustom = try #require(updatedState.arrangements.first { $0.id == customArrangement.id })
        #expect(updatedDefault.drawerViews[drawerId]?.showsMinimizedPanes == true)
        #expect(updatedCustom.drawerViews[drawerId]?.showsMinimizedPanes == false)
    }
}
