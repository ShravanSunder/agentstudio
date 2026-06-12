import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceTabBoundaryTests {
    @Test
    func hydrateSplitsGraphCursorAndPresentationOwners() {
        let primaryPaneId = UUID()
        let secondaryPaneId = UUID()
        let drawerPaneId = UUID()
        let drawerId = UUID()
        let defaultArrangementId = UUID()
        let focusedArrangementId = UUID()
        let tabId = UUID()
        let defaultArrangement = PaneArrangement(
            id: defaultArrangementId,
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: primaryPaneId),
            activePaneId: primaryPaneId
        )
        let focusedArrangement = PaneArrangement(
            id: focusedArrangementId,
            name: "Review",
            isDefault: false,
            layout: Layout.autoTiled([primaryPaneId, secondaryPaneId]),
            activePaneId: secondaryPaneId,
            drawerViews: [
                drawerId: DrawerView(
                    layout: DrawerGridLayout(topRow: Layout(paneId: drawerPaneId)),
                    activeChildId: drawerPaneId
                )
            ]
        )
        let tab = Tab(
            id: tabId,
            name: "Tab",
            allPaneIds: [primaryPaneId, secondaryPaneId, drawerPaneId],
            arrangements: [defaultArrangement, focusedArrangement],
            activeArrangementId: focusedArrangementId,
            zoomedPaneId: secondaryPaneId
        )
        let graphAtom = WorkspaceTabGraphAtom()
        let cursorAtom = WorkspaceArrangementCursorAtom()
        let presentationAtom = WorkspacePanePresentationAtom()
        let arrangementAtom = WorkspaceTabArrangementAtom(
            graphAtom: graphAtom,
            cursorAtom: cursorAtom,
            presentationAtom: presentationAtom
        )

        arrangementAtom.hydrate(persistedTabs: [tab], validPaneIds: Set(tab.allPaneIds))

        #expect(Set(graphAtom.tabState(tabId)?.allPaneIds ?? []) == [primaryPaneId, secondaryPaneId, drawerPaneId])
        #expect(graphAtom.tabState(tabId)?.arrangements.map(\.id) == [defaultArrangementId, focusedArrangementId])
        #expect(cursorAtom.activeArrangementId(forTab: tabId) == focusedArrangementId)
        #expect(cursorAtom.activePaneId(forArrangement: focusedArrangementId) == secondaryPaneId)
        #expect(cursorAtom.activeChildId(forArrangement: focusedArrangementId, drawerId: drawerId) == drawerPaneId)
        #expect(presentationAtom.zoomedPaneId(forTab: tabId) == secondaryPaneId)
        #expect(arrangementAtom.arrangementState(tabId)?.activeArrangementId == focusedArrangementId)
        #expect(arrangementAtom.arrangementState(tabId)?.arrangements[1].activePaneId == secondaryPaneId)
        #expect(
            arrangementAtom.arrangementState(tabId)?.arrangements[1].drawerViews[drawerId]?.activeChildId
                == drawerPaneId)
        #expect(arrangementAtom.arrangementState(tabId)?.zoomedPaneId == secondaryPaneId)
    }

    @Test
    func insertPaneRoutesGraphCursorAndPresentationTogether() {
        let targetPaneId = UUID()
        let insertedPaneId = UUID()
        let tab = Tab(paneId: targetPaneId)
        let graphAtom = WorkspaceTabGraphAtom()
        let cursorAtom = WorkspaceArrangementCursorAtom()
        let presentationAtom = WorkspacePanePresentationAtom()
        let arrangementAtom = WorkspaceTabArrangementAtom(
            graphAtom: graphAtom,
            cursorAtom: cursorAtom,
            presentationAtom: presentationAtom
        )
        arrangementAtom.hydrate(persistedTabs: [tab], validPaneIds: Set(tab.allPaneIds))
        presentationAtom.setZoomedPaneId(targetPaneId, forTab: tab.id)

        let didInsert = arrangementAtom.insertPane(
            insertedPaneId,
            inTab: tab.id,
            at: targetPaneId,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )

        #expect(didInsert)
        #expect(graphAtom.tabState(tab.id)?.allPaneIds == [targetPaneId, insertedPaneId])
        #expect(cursorAtom.activePaneId(forArrangement: tab.activeArrangementId) == insertedPaneId)
        #expect(presentationAtom.zoomedPaneId(forTab: tab.id) == nil)
        #expect(arrangementAtom.arrangementState(tab.id)?.activePaneId == insertedPaneId)
        #expect(arrangementAtom.arrangementState(tab.id)?.zoomedPaneId == nil)
    }

    @Test
    func registryExposesInjectedFacadeBackingOwners() {
        let shellCursorAtom = WorkspaceTabCursorAtom()
        let injectedShellAtom = WorkspaceTabShellAtom(cursorAtom: shellCursorAtom)
        let graphAtom = WorkspaceTabGraphAtom()
        let arrangementCursorAtom = WorkspaceArrangementCursorAtom()
        let presentationAtom = WorkspacePanePresentationAtom()
        let injectedArrangementAtom = WorkspaceTabArrangementAtom(
            graphAtom: graphAtom,
            cursorAtom: arrangementCursorAtom,
            presentationAtom: presentationAtom
        )

        let registry = AtomRegistry(
            workspaceTabCursor: shellCursorAtom,
            workspaceTabShell: injectedShellAtom,
            workspaceTabGraph: graphAtom,
            workspaceArrangementCursor: arrangementCursorAtom,
            workspacePanePresentation: presentationAtom,
            workspaceTabArrangement: injectedArrangementAtom
        )

        #expect(registry.workspaceTabShell === injectedShellAtom)
        #expect(registry.workspaceTabCursor === shellCursorAtom)
        #expect(registry.workspaceTabArrangement === injectedArrangementAtom)
        #expect(registry.workspaceTabGraph === graphAtom)
        #expect(registry.workspaceArrangementCursor === arrangementCursorAtom)
        #expect(registry.workspacePanePresentation === presentationAtom)
    }

    @Test
    func facadePreservesExplicitNilPaneAndDrawerCursors() {
        let firstPaneId = UUID()
        let secondPaneId = UUID()
        let firstDrawerPaneId = UUID()
        let secondDrawerPaneId = UUID()
        let drawerId = UUID()
        let arrangement = PaneArrangement(
            layout: Layout(paneId: firstPaneId)
                .inserting(
                    paneId: secondPaneId,
                    at: firstPaneId,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )!,
            activePaneId: firstPaneId,
            drawerViews: [
                drawerId: DrawerView(
                    layout: DrawerGridLayout(
                        topRow: Layout(paneId: firstDrawerPaneId)
                            .inserting(
                                paneId: secondDrawerPaneId,
                                at: firstDrawerPaneId,
                                direction: .horizontal,
                                position: .after,
                                sizingMode: .halveTarget
                            )!
                    ),
                    activeChildId: firstDrawerPaneId
                )
            ]
        )
        let tab = Tab(
            allPaneIds: [firstPaneId, secondPaneId, firstDrawerPaneId, secondDrawerPaneId],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )
        let graphAtom = WorkspaceTabGraphAtom()
        let cursorAtom = WorkspaceArrangementCursorAtom()
        let arrangementAtom = WorkspaceTabArrangementAtom(
            graphAtom: graphAtom,
            cursorAtom: cursorAtom,
            presentationAtom: WorkspacePanePresentationAtom()
        )
        arrangementAtom.hydrate(persistedTabs: [tab], validPaneIds: Set(tab.allPaneIds))

        _ = arrangementAtom.minimizePane(firstPaneId, inTab: tab.id)
        _ = arrangementAtom.minimizePane(secondPaneId, inTab: tab.id)
        _ = arrangementAtom.minimizeDrawerPane(firstDrawerPaneId, drawerId: drawerId, tabId: tab.id)
        _ = arrangementAtom.minimizeDrawerPane(secondDrawerPaneId, drawerId: drawerId, tabId: tab.id)

        #expect(cursorAtom.activePaneId(forArrangement: arrangement.id) == nil)
        #expect(cursorAtom.activeChildId(forArrangement: arrangement.id, drawerId: drawerId) == nil)
        #expect(arrangementAtom.arrangementState(tab.id)?.arrangements[0].activePaneId == nil)
        #expect(arrangementAtom.arrangementState(tab.id)?.arrangements[0].drawerViews[drawerId]?.activeChildId == nil)
        #expect(graphAtom.tabState(tab.id)?.arrangements[0].minimizedPaneIds == Set([firstPaneId, secondPaneId]))
        #expect(
            graphAtom.tabState(tab.id)?.arrangements[0].drawerViews[drawerId]?.minimizedPaneIds
                == Set([firstDrawerPaneId, secondDrawerPaneId]))
    }

    @Test
    func removePaneClearsPresentationOwnerZoom() {
        let paneId = UUID()
        let siblingPaneId = UUID()
        let tab = Tab(
            allPaneIds: [paneId, siblingPaneId],
            arrangements: [
                PaneArrangement(
                    layout: Layout(paneId: paneId)
                        .inserting(
                            paneId: siblingPaneId,
                            at: paneId,
                            direction: .horizontal,
                            position: .after,
                            sizingMode: .halveTarget
                        )!,
                    activePaneId: paneId
                )
            ],
            activeArrangementId: UUID()
        )
        let arrangement = tab.arrangements[0]
        let presentationAtom = WorkspacePanePresentationAtom()
        let arrangementAtom = WorkspaceTabArrangementAtom(
            graphAtom: WorkspaceTabGraphAtom(),
            cursorAtom: WorkspaceArrangementCursorAtom(),
            presentationAtom: presentationAtom
        )
        let hydratedTab = Tab(
            id: tab.id,
            name: tab.name,
            allPaneIds: tab.allPaneIds,
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )
        arrangementAtom.hydrate(persistedTabs: [hydratedTab], validPaneIds: Set(hydratedTab.allPaneIds))
        presentationAtom.setZoomedPaneId(paneId, forTab: hydratedTab.id)

        arrangementAtom.removePaneReferences(Set([paneId]))

        #expect(presentationAtom.zoomedPaneId(forTab: hydratedTab.id) == nil)
        #expect(arrangementAtom.arrangementState(hydratedTab.id)?.zoomedPaneId == nil)
    }

    @Test
    func movePaneAcrossTabsClearsSourceAndDestinationPresentationZoom() {
        let movingPaneId = UUID()
        let sourceSiblingPaneId = UUID()
        let destinationPaneId = UUID()
        let sourceTab = Tab(
            allPaneIds: [movingPaneId, sourceSiblingPaneId],
            arrangements: [
                PaneArrangement(
                    layout: Layout(paneId: movingPaneId)
                        .inserting(
                            paneId: sourceSiblingPaneId,
                            at: movingPaneId,
                            direction: .horizontal,
                            position: .after,
                            sizingMode: .halveTarget
                        )!,
                    activePaneId: movingPaneId
                )
            ],
            activeArrangementId: UUID()
        )
        let destinationTab = Tab(paneId: destinationPaneId)
        let sourceArrangement = sourceTab.arrangements[0]
        let hydratedSourceTab = Tab(
            id: sourceTab.id,
            name: sourceTab.name,
            allPaneIds: sourceTab.allPaneIds,
            arrangements: [sourceArrangement],
            activeArrangementId: sourceArrangement.id
        )
        let presentationAtom = WorkspacePanePresentationAtom()
        let arrangementAtom = WorkspaceTabArrangementAtom(
            graphAtom: WorkspaceTabGraphAtom(),
            cursorAtom: WorkspaceArrangementCursorAtom(),
            presentationAtom: presentationAtom
        )
        arrangementAtom.hydrate(
            persistedTabs: [hydratedSourceTab, destinationTab],
            validPaneIds: Set(hydratedSourceTab.allPaneIds + destinationTab.allPaneIds)
        )
        presentationAtom.setZoomedPaneId(movingPaneId, forTab: hydratedSourceTab.id)
        presentationAtom.setZoomedPaneId(destinationPaneId, forTab: destinationTab.id)

        let result = arrangementAtom.movePaneAcrossTabs(
            CrossTabPaneMoveMutation(
                request: CrossTabPaneMoveRequest(
                    paneId: movingPaneId,
                    sourceTabId: hydratedSourceTab.id,
                    destTabId: destinationTab.id,
                    targetPaneId: destinationPaneId,
                    direction: .horizontal,
                    position: .after
                ),
                drawerId: nil,
                drawerPaneIds: []
            ))

        #expect(result?.sourceTabClosed == false)
        #expect(presentationAtom.zoomedPaneId(forTab: hydratedSourceTab.id) == nil)
        #expect(presentationAtom.zoomedPaneId(forTab: destinationTab.id) == nil)
        #expect(arrangementAtom.arrangementState(hydratedSourceTab.id)?.zoomedPaneId == nil)
        #expect(arrangementAtom.arrangementState(destinationTab.id)?.zoomedPaneId == nil)
    }
}
