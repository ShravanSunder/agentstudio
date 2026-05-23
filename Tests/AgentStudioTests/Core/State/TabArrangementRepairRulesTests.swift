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
                minimizedPaneIds: [MainPaneId(paneB)]
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
                minimizedPaneIds: [MainPaneId(stalePane)]
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
                        activeChildId: DrawerPaneId(staleDrawerPane),
                        minimizedPaneIds: [DrawerPaneId(staleDrawerPane)]
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
        #expect(drawerView.activeChildId?.rawValue == validDrawerPane)
    }
}
