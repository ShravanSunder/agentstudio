import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("WorkspaceArrangementViewDerived")
struct WorkspaceArrangementViewDerivedTests {
    @Test
    func activeVisiblePaneIds_derivesMinimizedVisibilityFromManagementState() {
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
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: layout,
            activePaneId: paneA
        )
        let userArrangement = PaneArrangement(
            name: "Layout 1",
            isDefault: false,
            layout: layout,
            minimizedPaneIds: [paneB],
            activePaneId: paneA
        )
        let tab = Tab(
            name: "Tab",
            allPaneIds: [paneA, paneB],
            arrangements: [defaultArrangement, userArrangement],
            activeArrangementId: userArrangement.id
        )
        let tabLayout = WorkspaceTabLayoutAtom()
        let paneAtom = WorkspacePaneAtom()
        let managementLayer = ManagementLayerAtom()
        paneAtom.addPane(makePane(id: paneA))
        paneAtom.addPane(makePane(id: paneB))
        tabLayout.appendTab(tab)
        let derived = WorkspaceArrangementViewDerived(
            tabLayoutAtom: tabLayout,
            paneAtom: paneAtom,
            managementLayerAtom: managementLayer
        )

        #expect(derived.activeVisiblePaneIds(forTab: tab.id) == [paneA])

        managementLayer.activate()

        #expect(derived.activeVisiblePaneIds(forTab: tab.id) == [paneA, paneB])
    }

    @Test
    func activeVisiblePaneIds_excludesBackgroundedCanonicalLayoutPanes() {
        let activePane = makePane(id: UUIDv7.generate())
        let backgroundedPane = Pane(
            id: UUIDv7.generate(),
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: .generateUUIDv7()
                )
            ),
            metadata: PaneMetadata(),
            residency: .backgrounded
        )
        let layout = Layout(paneId: activePane.id)
            .inserting(
                paneId: backgroundedPane.id,
                at: activePane.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )!
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: layout,
            activePaneId: activePane.id
        )
        let tab = Tab(
            name: "Tab",
            allPaneIds: [activePane.id, backgroundedPane.id],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )
        let tabLayout = WorkspaceTabLayoutAtom()
        let paneAtom = WorkspacePaneAtom()
        let managementLayer = ManagementLayerAtom()
        paneAtom.addPane(activePane)
        paneAtom.addPane(backgroundedPane)
        tabLayout.appendTab(tab)
        let derived = WorkspaceArrangementViewDerived(
            tabLayoutAtom: tabLayout,
            paneAtom: paneAtom,
            managementLayerAtom: managementLayer
        )

        #expect(derived.activeVisiblePaneIds(forTab: tab.id) == [activePane.id])

        managementLayer.activate()

        #expect(derived.activeVisiblePaneIds(forTab: tab.id) == [activePane.id])
    }

    @Test
    func activeLayout_excludesBackgroundedCanonicalSegments() throws {
        let firstActivePane = makePane(id: UUIDv7.generate())
        let backgroundedPane = Pane(
            id: UUIDv7.generate(),
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: .generateUUIDv7()
                )
            ),
            metadata: PaneMetadata(),
            residency: .backgrounded
        )
        let secondActivePane = makePane(id: UUIDv7.generate())
        let layout = Layout(
            panes: [
                .init(paneId: firstActivePane.id, ratio: 0.25),
                .init(paneId: backgroundedPane.id, ratio: 0.5),
                .init(paneId: secondActivePane.id, ratio: 0.25),
            ],
            dividerIds: [UUIDv7.generate(), UUIDv7.generate()]
        )
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: layout,
            activePaneId: firstActivePane.id
        )
        let tab = Tab(
            name: "Tab",
            allPaneIds: [firstActivePane.id, backgroundedPane.id, secondActivePane.id],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )
        let tabLayout = WorkspaceTabLayoutAtom()
        let paneAtom = WorkspacePaneAtom()
        let managementLayer = ManagementLayerAtom()
        paneAtom.addPane(firstActivePane)
        paneAtom.addPane(backgroundedPane)
        paneAtom.addPane(secondActivePane)
        tabLayout.appendTab(tab)
        let derived = WorkspaceArrangementViewDerived(
            tabLayoutAtom: tabLayout,
            paneAtom: paneAtom,
            managementLayerAtom: managementLayer
        )

        let activeLayout = try #require(derived.activeLayout(forTab: tab.id))

        #expect(activeLayout.paneIds == [firstActivePane.id, secondActivePane.id])
        #expect(activeLayout.paneRatio(firstActivePane.id) == 0.5)
        #expect(activeLayout.paneRatio(secondActivePane.id) == 0.5)
        #expect(activeLayout.dividerIds.count == 1)
    }

    @Test
    func activePaneId_fallsBackToFirstActiveResidencyLayoutPane() {
        var backgroundedCanonicalPane = makePane(id: UUIDv7.generate())
        backgroundedCanonicalPane.residency = .backgrounded
        let activeFallbackPane = makePane(id: UUIDv7.generate())
        let layout = Layout(paneId: backgroundedCanonicalPane.id)
            .inserting(
                paneId: activeFallbackPane.id,
                at: backgroundedCanonicalPane.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )!
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: layout,
            activePaneId: backgroundedCanonicalPane.id
        )
        let tab = Tab(
            name: "Tab",
            allPaneIds: [backgroundedCanonicalPane.id, activeFallbackPane.id],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )
        let tabLayout = WorkspaceTabLayoutAtom()
        let paneAtom = WorkspacePaneAtom()
        let managementLayer = ManagementLayerAtom()
        paneAtom.addPane(backgroundedCanonicalPane)
        paneAtom.addPane(activeFallbackPane)
        tabLayout.appendTab(tab)
        let derived = WorkspaceArrangementViewDerived(
            tabLayoutAtom: tabLayout,
            paneAtom: paneAtom,
            managementLayerAtom: managementLayer
        )

        #expect(derived.activePaneId(forTab: tab.id) == activeFallbackPane.id)
        #expect(tabLayout.tab(tab.id)?.activePaneId == backgroundedCanonicalPane.id)
    }

    @Test
    func drawerVisiblePaneIds_derivesMinimizedVisibilityFromManagementState() {
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
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: parentWithDrawerPanes.id),
            activePaneId: parentWithDrawerPanes.id,
            drawerViews: [
                drawer.drawerId: DrawerView(
                    layout: drawerLayout,
                    activeChildId: drawerPaneA.id
                )
            ]
        )
        let userArrangement = PaneArrangement(
            name: "Layout 1",
            isDefault: false,
            layout: Layout(paneId: parentWithDrawerPanes.id),
            activePaneId: parentWithDrawerPanes.id,
            drawerViews: [
                drawer.drawerId: DrawerView(
                    layout: drawerLayout,
                    activeChildId: drawerPaneA.id,
                    minimizedPaneIds: [drawerPaneB.id]
                )
            ]
        )
        let tab = Tab(
            name: "Tab",
            allPaneIds: [parentWithDrawerPanes.id],
            arrangements: [defaultArrangement, userArrangement],
            activeArrangementId: userArrangement.id
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

        managementLayer.activate()

        #expect(derived.drawerVisiblePaneIds(forParent: parentWithDrawerPanes.id) == [drawerPaneA.id, drawerPaneB.id])
    }

    @Test
    func drawerVisiblePaneIds_excludesBackgroundedCanonicalDrawerChildren() {
        var parentPane = makePane(id: UUIDv7.generate())
        let activeDrawerPane = makeDrawerChild(id: UUIDv7.generate(), parentPaneId: parentPane.id)
        var backgroundedDrawerPane = makeDrawerChild(id: UUIDv7.generate(), parentPaneId: parentPane.id)
        backgroundedDrawerPane.residency = .backgrounded
        parentPane.withDrawer { drawer in
            drawer.paneIds = [activeDrawerPane.id, backgroundedDrawerPane.id]
            drawer.isExpanded = true
        }
        let drawerID = parentPane.drawer!.drawerId
        let drawerLayout = DrawerGridLayout(
            topRow: Layout(paneId: activeDrawerPane.id)
                .inserting(
                    paneId: backgroundedDrawerPane.id,
                    at: activeDrawerPane.id,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )!
        )
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: parentPane.id),
            activePaneId: parentPane.id,
            drawerViews: [
                drawerID: DrawerView(
                    layout: drawerLayout,
                    activeChildId: activeDrawerPane.id
                )
            ]
        )
        let tab = Tab(
            name: "Tab",
            allPaneIds: [parentPane.id, activeDrawerPane.id, backgroundedDrawerPane.id],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )
        let tabLayout = WorkspaceTabLayoutAtom()
        let paneAtom = WorkspacePaneAtom()
        let managementLayer = ManagementLayerAtom()
        paneAtom.addPane(parentPane)
        paneAtom.addPane(activeDrawerPane)
        paneAtom.addPane(backgroundedDrawerPane)
        tabLayout.appendTab(tab)
        let derived = WorkspaceArrangementViewDerived(
            tabLayoutAtom: tabLayout,
            paneAtom: paneAtom,
            managementLayerAtom: managementLayer
        )

        #expect(derived.drawerVisiblePaneIds(forParent: parentPane.id) == [activeDrawerPane.id])

        managementLayer.activate()

        #expect(derived.drawerVisiblePaneIds(forParent: parentPane.id) == [activeDrawerPane.id])
    }

    @Test
    func drawerView_returnsEmptyViewForExpandedEmptyDrawer() {
        var parentPane = makePane(id: UUIDv7.generate())
        parentPane.withDrawer { drawer in
            drawer.isExpanded = true
            drawer.paneIds = []
        }
        let drawerId = parentPane.drawer!.drawerId
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: parentPane.id),
            activePaneId: parentPane.id
        )
        let tab = Tab(
            name: "Tab",
            allPaneIds: [parentPane.id],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )
        let tabLayout = WorkspaceTabLayoutAtom()
        let paneAtom = WorkspacePaneAtom()
        let managementLayer = ManagementLayerAtom()
        paneAtom.addPane(parentPane)
        tabLayout.appendTab(tab)
        let derived = WorkspaceArrangementViewDerived(
            tabLayoutAtom: tabLayout,
            paneAtom: paneAtom,
            managementLayerAtom: managementLayer
        )

        let drawerView = derived.drawerView(forParent: parentPane.id)

        #expect(drawerView?.layout.isEmpty == true)
        #expect(drawerView?.activeChildId == nil)
        #expect(derived.drawerVisiblePaneIds(forParent: parentPane.id).isEmpty)
        #expect(tab.activeArrangement.drawerViews[drawerId] == nil)
    }

    @Test
    func drawerView_returnsNilForNonEmptyDrawerWithoutArrangementView() {
        var parentPane = makePane(id: UUIDv7.generate())
        let drawerPane = makeDrawerChild(id: UUIDv7.generate(), parentPaneId: parentPane.id)
        parentPane.withDrawer { drawer in
            drawer.isExpanded = true
            drawer.paneIds = [drawerPane.id]
        }
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: parentPane.id),
            activePaneId: parentPane.id
        )
        let tab = Tab(
            name: "Tab",
            allPaneIds: [parentPane.id],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )
        let tabLayout = WorkspaceTabLayoutAtom()
        let paneAtom = WorkspacePaneAtom()
        let managementLayer = ManagementLayerAtom()
        paneAtom.addPane(parentPane)
        paneAtom.addPane(drawerPane)
        tabLayout.appendTab(tab)
        let derived = WorkspaceArrangementViewDerived(
            tabLayoutAtom: tabLayout,
            paneAtom: paneAtom,
            managementLayerAtom: managementLayer
        )

        #expect(derived.drawerView(forParent: parentPane.id) == nil)
    }

    private func makePane(id: UUID) -> Pane {
        Pane(
            id: id,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())),
            metadata: PaneMetadata()
        )
    }

    private func makeDrawerChild(id: UUID, parentPaneId: UUID) -> Pane {
        Pane(
            id: id,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())),
            metadata: PaneMetadata(),
            kind: .drawerChild(parentPaneId: parentPaneId)
        )
    }
}
