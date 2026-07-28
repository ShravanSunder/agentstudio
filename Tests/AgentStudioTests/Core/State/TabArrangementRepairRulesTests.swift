import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct TabArrangementRepairRulesTests {
    @Test
    func removingPane_removesItFromLayoutAndMinimizedSet() {
        let paneA = UUID()
        let paneB = UUID()
        let arrangements = [
            PaneArrangement(
                name: "Default",
                isDefault: true,
                layout: Layout(paneId: paneA)
                    .inserting(
                        paneId: paneB, at: paneA, direction: .horizontal, position: .after, sizingMode: .halveTarget)!,
                minimizedPaneIds: [paneB]
            )
        ]

        let updated = TabArrangementRepairRules.removingPane(paneB, from: arrangements)

        #expect(updated[0].layout.paneIds == [paneA])
        #expect(updated[0].minimizedPaneIds.isEmpty)
    }

    @Test
    func pruningInvalidPaneIds_removesThemFromAllArrangementCollections() {
        let paneA = UUID()
        let stalePane = UUID()
        let arrangements = [
            PaneArrangement(
                name: "Default",
                isDefault: true,
                layout: Layout(paneId: paneA)
                    .inserting(
                        paneId: stalePane, at: paneA, direction: .horizontal, position: .after, sizingMode: .halveTarget
                    )!,
                minimizedPaneIds: [stalePane]
            )
        ]

        let updated = TabArrangementRepairRules.pruningInvalidPaneIds(
            validPaneIds: [paneA],
            from: arrangements
        )

        #expect(updated[0].layout.paneIds == [paneA])
        #expect(updated[0].minimizedPaneIds.isEmpty)
    }

    @Test
    func pruningInvalidPaneIds_repairsDrawerViews() throws {
        let parentPane = UUID()
        let drawerId = UUID()
        let validDrawerPane = UUID()
        let staleDrawerPane = UUID()
        let drawerLayout = DrawerGridLayout(
            topRow: Layout(paneId: validDrawerPane)
                .inserting(
                    paneId: staleDrawerPane,
                    at: validDrawerPane,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )!
        )
        let arrangements = [
            PaneArrangement(
                name: "Default",
                isDefault: true,
                layout: Layout(paneId: parentPane),
                drawerViews: [
                    drawerId: DrawerView(
                        layout: drawerLayout,
                        activeChildId: staleDrawerPane,
                        minimizedPaneIds: [staleDrawerPane]
                    )
                ]
            )
        ]

        let updated = TabArrangementRepairRules.pruningInvalidPaneIds(
            validPaneIds: [parentPane, validDrawerPane],
            from: arrangements
        )

        let drawerView = try #require(updated[0].drawerViews[drawerId])
        #expect(drawerView.layout.paneIds == [validDrawerPane])
        #expect(drawerView.minimizedPaneIds.isEmpty)
        #expect(drawerView.activeChildId == validDrawerPane)
    }

    @Test
    func pruningInvalidPaneIds_clearsDefaultMinimizedPanesButPreservesUserLayoutState() throws {
        let paneA = UUID()
        let paneB = UUID()
        let drawerPane = UUID()
        let drawerId = UUID()
        var defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneA),
            drawerViews: [
                drawerId: DrawerView(
                    layout: DrawerGridLayout(topRow: Layout(paneId: drawerPane))
                )
            ]
        )
        defaultArrangement.minimizedPaneIds = [paneA]
        let userLayout = PaneArrangement(
            name: "Layout 1",
            isDefault: false,
            layout: Layout.autoTiled([paneB, paneA]),
            minimizedPaneIds: [paneB]
        )

        let updated = TabArrangementRepairRules.pruningInvalidPaneIds(
            validPaneIds: [paneA, paneB, drawerPane],
            from: [defaultArrangement, userLayout]
        )
        let updatedDefault = try #require(updated.first(where: { $0.isDefault }))
        let updatedUserLayout = try #require(updated.first(where: { !$0.isDefault }))

        #expect(updatedDefault.layout.paneIds == [paneA])
        #expect(updatedDefault.minimizedPaneIds.isEmpty)
        #expect(updatedDefault.drawerViews[drawerId]?.layout.paneIds == [drawerPane])
        #expect(updatedUserLayout.layout.paneIds == [paneB, paneA])
        #expect(updatedUserLayout.minimizedPaneIds == Set([paneB]))
    }
}
