import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceTabBoundaryTests {
    @Test
    func domainReplacementSplitsGraphAndCursorOwners() {
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
            activeArrangementId: focusedArrangementId
        )
        let graphAtom = WorkspaceTabGraphAtom()
        let cursorAtom = WorkspaceArrangementCursorAtom()
        let presentationAtom = WorkspacePanePresentationAtom()
        let arrangementAtom = WorkspaceTabArrangementAtom(
            graphAtom: graphAtom,
            cursorAtom: cursorAtom,
            presentationAtom: presentationAtom
        )

        replaceTabComposition([tab], in: arrangementAtom)

        #expect(Set(graphAtom.tabState(tabId)?.allPaneIds ?? []) == [primaryPaneId, secondaryPaneId, drawerPaneId])
        #expect(graphAtom.tabState(tabId)?.arrangements.map(\.id) == [defaultArrangementId, focusedArrangementId])
        #expect(cursorAtom.activeArrangementId(forTab: tabId) == focusedArrangementId)
        #expect(cursorAtom.activePaneId(forArrangement: focusedArrangementId) == secondaryPaneId)
        #expect(cursorAtom.activeChildId(forArrangement: focusedArrangementId, drawerId: drawerId) == drawerPaneId)
        #expect(arrangementAtom.arrangementState(tabId)?.activeArrangementId == focusedArrangementId)
        #expect(arrangementAtom.arrangementState(tabId)?.arrangements[1].activePaneId == secondaryPaneId)
        #expect(
            arrangementAtom.arrangementState(tabId)?.arrangements[1].drawerViews[drawerId]?.activeChildId
                == drawerPaneId)
    }

    @Test
    func insertPaneRoutesGraphAndCursorTogether() {
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
        replaceTabComposition([tab], in: arrangementAtom)

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
        #expect(arrangementAtom.arrangementState(tab.id)?.activePaneId == insertedPaneId)
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
        let layout = Layout(paneId: firstPaneId)
            .inserting(
                paneId: secondPaneId,
                at: firstPaneId,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )!
        let drawerView = DrawerView(
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
        let defaultArrangement = PaneArrangement(
            layout: layout,
            activePaneId: firstPaneId,
            drawerViews: [drawerId: drawerView]
        )
        let arrangement = PaneArrangement(
            name: "Layout 1",
            isDefault: false,
            layout: layout,
            activePaneId: firstPaneId,
            drawerViews: [drawerId: drawerView]
        )
        let tab = Tab(
            allPaneIds: [firstPaneId, secondPaneId, firstDrawerPaneId, secondDrawerPaneId],
            arrangements: [defaultArrangement, arrangement],
            activeArrangementId: arrangement.id
        )
        let graphAtom = WorkspaceTabGraphAtom()
        let cursorAtom = WorkspaceArrangementCursorAtom()
        let arrangementAtom = WorkspaceTabArrangementAtom(
            graphAtom: graphAtom,
            cursorAtom: cursorAtom,
            presentationAtom: WorkspacePanePresentationAtom()
        )
        replaceTabComposition([tab], in: arrangementAtom)

        _ = arrangementAtom.minimizePane(firstPaneId, inTab: tab.id)
        _ = arrangementAtom.minimizePane(secondPaneId, inTab: tab.id)
        _ = arrangementAtom.minimizeDrawerPane(firstDrawerPaneId, drawerId: drawerId, tabId: tab.id)
        _ = arrangementAtom.minimizeDrawerPane(secondDrawerPaneId, drawerId: drawerId, tabId: tab.id)

        #expect(cursorAtom.activePaneId(forArrangement: arrangement.id) == nil)
        #expect(cursorAtom.activeChildId(forArrangement: arrangement.id, drawerId: drawerId) == nil)
        let projectedArrangement = arrangementAtom.arrangementState(tab.id)?.arrangements.first {
            $0.id == arrangement.id
        }
        let graphArrangement = graphAtom.tabState(tab.id)?.arrangements.first {
            $0.id == arrangement.id
        }
        #expect(projectedArrangement?.activePaneId == nil)
        #expect(projectedArrangement?.drawerViews[drawerId]?.activeChildId == nil)
        #expect(graphArrangement?.minimizedPaneIds == Set([firstPaneId, secondPaneId]))
        #expect(
            graphArrangement?.drawerViews[drawerId]?.minimizedPaneIds
                == Set([firstDrawerPaneId, secondDrawerPaneId]))
    }

    private func replaceTabComposition(
        _ tabs: [Tab],
        in arrangementAtom: WorkspaceTabArrangementAtom
    ) {
        let arrangementStates = tabs.map {
            TabArrangementState(
                tabId: $0.id,
                allPaneIds: $0.allPaneIds,
                arrangements: $0.arrangements,
                activeArrangementId: $0.activeArrangementId
            )
        }
        var activeArrangementIdsByTabId: [UUID: UUID] = [:]
        var paneCursorsByArrangementId: [UUID: ArrangementPaneCursorState] = [:]
        var drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState] = [:]
        for tab in tabs {
            activeArrangementIdsByTabId[tab.id] = tab.activeArrangementId
            for arrangement in tab.arrangements {
                paneCursorsByArrangementId[arrangement.id] = .init(activePaneId: arrangement.activePaneId)
                for (drawerId, drawerView) in arrangement.drawerViews {
                    drawerCursorsByKey[
                        ArrangementDrawerCursorKey(arrangementId: arrangement.id, drawerId: drawerId)
                    ] = .init(activeChildId: drawerView.activeChildId)
                }
            }
        }

        arrangementAtom.graphAtom.replaceStates(arrangementStates.map(TabGraphState.init))
        arrangementAtom.cursorAtom.replaceCursors(
            activeArrangementIdsByTabId: activeArrangementIdsByTabId,
            paneCursorsByArrangementId: paneCursorsByArrangementId,
            drawerCursorsByKey: drawerCursorsByKey
        )
    }
}
