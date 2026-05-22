import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Cross-tab pane move")
struct CrossTabPaneMoveTests {
    @Test
    func movePaneAcrossTabs_removesFromEverySourceArrangementAndInsertsIntoEveryDestinationArrangement() throws {
        let sourcePaneId = UUID()
        let sourceSiblingId = UUID()
        let targetPaneId = UUID()
        let targetSiblingId = UUID()
        let drawerId = UUID()
        let drawerPaneIds = [UUID(), UUID()]

        let sourceDefault = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout.autoTiled([sourcePaneId, sourceSiblingId]),
            activePaneId: sourcePaneId,
            drawerViews: [drawerId: DrawerView(layout: DrawerGridLayout(topRow: Layout.autoTiled(drawerPaneIds)))]
        )
        let sourceCustom = PaneArrangement(
            name: "Source Focus",
            isDefault: false,
            layout: Layout(paneId: sourcePaneId),
            minimizedPaneIds: [sourcePaneId],
            showsMinimizedPanes: false,
            activePaneId: sourcePaneId,
            drawerViews: [drawerId: DrawerView(layout: DrawerGridLayout(topRow: Layout.autoTiled(drawerPaneIds)))]
        )
        let sourceTab = Tab(
            name: "Source",
            allPaneIds: [sourcePaneId, sourceSiblingId],
            arrangements: [sourceDefault, sourceCustom],
            activeArrangementId: sourceCustom.id
        )
        let destinationDefault = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout.autoTiled([targetPaneId, targetSiblingId]),
            activePaneId: targetPaneId
        )
        let destinationCustom = PaneArrangement(
            name: "Destination Focus",
            isDefault: false,
            layout: Layout(paneId: targetPaneId),
            activePaneId: targetPaneId
        )
        let destinationTab = Tab(
            name: "Destination",
            allPaneIds: [targetPaneId, targetSiblingId],
            arrangements: [destinationDefault, destinationCustom],
            activeArrangementId: destinationCustom.id
        )
        let tabLayout = WorkspaceTabLayoutAtom()
        tabLayout.appendTab(sourceTab)
        tabLayout.appendTab(destinationTab)

        let result = tabLayout.movePaneAcrossTabs(
            CrossTabPaneMoveMutation(
                request: CrossTabPaneMoveRequest(
                    paneId: sourcePaneId,
                    sourceTabId: sourceTab.id,
                    destTabId: destinationTab.id,
                    targetPaneId: targetPaneId,
                    direction: .horizontal,
                    position: .after
                ),
                drawerId: drawerId,
                drawerPaneIds: drawerPaneIds
            )
        )

        #expect(result?.sourceTabClosed == false)
        let updatedSource = try #require(tabLayout.tab(sourceTab.id))
        #expect(updatedSource.allPaneIds == [sourceSiblingId])
        #expect(updatedSource.arrangements.allSatisfy { !$0.layout.contains(sourcePaneId) })
        #expect(updatedSource.arrangements.allSatisfy { !$0.minimizedPaneIds.contains(sourcePaneId) })
        #expect(updatedSource.arrangements.allSatisfy { $0.drawerViews[drawerId] == nil })

        let updatedDestination = try #require(tabLayout.tab(destinationTab.id))
        #expect(updatedDestination.allPaneIds == [targetPaneId, targetSiblingId, sourcePaneId])
        #expect(updatedDestination.activePaneId == sourcePaneId)
        #expect(updatedDestination.activePaneIds == [targetPaneId, sourcePaneId])
        let updatedDestinationDefault = try #require(updatedDestination.arrangements.first { $0.isDefault })
        #expect(updatedDestinationDefault.layout.paneIds == [targetPaneId, targetSiblingId, sourcePaneId])
        for arrangement in updatedDestination.arrangements {
            let drawerView = try #require(arrangement.drawerViews[drawerId])
            #expect(drawerView.layout.paneIds == drawerPaneIds)
            #expect(drawerView.activeChildId == drawerPaneIds[0])
            #expect(drawerView.minimizedPaneIds.isEmpty)
        }
    }

    @Test
    func movePaneAcrossTabs_closesSourceTabWhenLastMainPaneMoves() throws {
        let sourcePaneId = UUID()
        let targetPaneId = UUID()
        let sourceTab = Tab(paneId: sourcePaneId, name: "Source")
        let destinationTab = Tab(paneId: targetPaneId, name: "Destination")
        let tabLayout = WorkspaceTabLayoutAtom()
        tabLayout.appendTab(sourceTab)
        tabLayout.appendTab(destinationTab)

        let result = tabLayout.movePaneAcrossTabs(
            CrossTabPaneMoveMutation(
                request: CrossTabPaneMoveRequest(
                    paneId: sourcePaneId,
                    sourceTabId: sourceTab.id,
                    destTabId: destinationTab.id,
                    targetPaneId: targetPaneId,
                    direction: .horizontal,
                    position: .after
                ),
                drawerId: nil,
                drawerPaneIds: []
            )
        )

        #expect(result?.sourceTabClosed == true)
        #expect(tabLayout.tab(sourceTab.id) == nil)
        #expect(tabLayout.tab(destinationTab.id)?.allPaneIds == [targetPaneId, sourcePaneId])
        #expect(tabLayout.activeTabId == destinationTab.id)
    }
}
