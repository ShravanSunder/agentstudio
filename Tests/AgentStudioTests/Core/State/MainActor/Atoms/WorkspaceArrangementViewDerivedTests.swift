import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceArrangementViewDerived")
struct WorkspaceArrangementViewDerivedTests {
    @Test
    func activeVisiblePaneIds_hideMinimizedPanesUntilManagementOverride() {
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(
                paneId: paneB,
                at: paneA,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )!
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: layout,
            minimizedPaneIds: [paneB],
            showsMinimizedPanes: false,
            activePaneId: paneA
        )
        let tab = Tab(
            name: "Tab",
            allPaneIds: [paneA, paneB],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )
        let tabLayout = WorkspaceTabLayoutAtom()
        let paneAtom = WorkspacePaneAtom()
        let managementLayer = ManagementLayerAtom()
        tabLayout.appendTab(tab)
        let derived = WorkspaceArrangementViewDerived(
            tabLayoutAtom: tabLayout,
            paneAtom: paneAtom,
            managementLayerAtom: managementLayer
        )

        #expect(derived.activeVisiblePaneIds(forTab: tab.id) == [paneA])
        #expect(derived.effectiveShowsMinimizedPanes(forTab: tab.id) == false)

        managementLayer.activate()

        #expect(derived.activeVisiblePaneIds(forTab: tab.id) == [paneA, paneB])
        #expect(derived.effectiveShowsMinimizedPanes(forTab: tab.id) == true)
    }

    @Test
    func drawerVisiblePaneIds_hideMinimizedDrawerPanesUntilManagementOverride() {
        let parentPane = makePane(id: UUIDv7.generate())
        let drawerPaneA = makeDrawerChild(id: UUIDv7.generate(), parentPaneId: parentPane.id)
        let drawerPaneB = makeDrawerChild(id: UUIDv7.generate(), parentPaneId: parentPane.id)
        var parentWithDrawerPanes = parentPane
        parentWithDrawerPanes.withDrawer { drawer in
            drawer.paneIds = [drawerPaneA.id, drawerPaneB.id]
        }
        let drawer = parentWithDrawerPanes.drawer!
        let drawerLayout = DrawerGridLayout(
            topRow: Layout(paneId: drawerPaneA.id)
                .inserting(
                    paneId: drawerPaneB.id,
                    at: drawerPaneA.id,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )!
        )
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: parentWithDrawerPanes.id),
            activePaneId: parentWithDrawerPanes.id,
            drawerViews: [
                drawer.drawerId: DrawerView(
                    layout: drawerLayout,
                    activeChildId: drawerPaneA.id,
                    minimizedPaneIds: [drawerPaneB.id],
                    showsMinimizedPanes: false
                )
            ]
        )
        let tab = Tab(
            name: "Tab",
            allPaneIds: [parentWithDrawerPanes.id],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )
        let tabLayout = WorkspaceTabLayoutAtom()
        let paneAtom = WorkspacePaneAtom()
        let managementLayer = ManagementLayerAtom()
        paneAtom.addPane(parentWithDrawerPanes)
        paneAtom.addPane(drawerPaneA)
        paneAtom.addPane(drawerPaneB)
        tabLayout.appendTab(tab)
        let derived = WorkspaceArrangementViewDerived(
            tabLayoutAtom: tabLayout,
            paneAtom: paneAtom,
            managementLayerAtom: managementLayer
        )

        #expect(derived.drawerVisiblePaneIds(forParent: parentWithDrawerPanes.id) == [drawerPaneA.id])
        #expect(derived.effectiveShowsMinimizedDrawerPanes(forParent: parentWithDrawerPanes.id) == false)

        managementLayer.activate()

        #expect(derived.drawerVisiblePaneIds(forParent: parentWithDrawerPanes.id) == [drawerPaneA.id, drawerPaneB.id])
        #expect(derived.effectiveShowsMinimizedDrawerPanes(forParent: parentWithDrawerPanes.id) == true)
    }

    private func makePane(id: UUID) -> Pane {
        Pane(
            id: id,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: nil))
        )
    }

    private func makeDrawerChild(id: UUID, parentPaneId: UUID) -> Pane {
        Pane(
            id: id,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: nil)),
            kind: .drawerChild(parentPaneId: parentPaneId)
        )
    }
}
