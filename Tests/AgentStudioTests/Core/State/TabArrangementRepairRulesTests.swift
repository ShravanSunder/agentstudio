import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct TabArrangementRepairRulesTests {
    @Test
    func removingPane_removesItFromLayoutVisibleAndMinimizedSets() {
        let paneA = UUID()
        let paneB = UUID()
        let arrangements = [
            PaneArrangement(
                name: "Default",
                isDefault: true,
                layout: Layout(paneId: paneA)
                    .inserting(
                        paneId: paneB, at: paneA, direction: .horizontal, position: .after, sizingMode: .halveTarget),
                visiblePaneIds: [paneA, paneB],
                minimizedPaneIds: [paneB]
            )
        ]

        let updated = TabArrangementRepairRules.removingPane(paneB, from: arrangements)

        #expect(updated[0].layout.paneIds == [paneA])
        #expect(updated[0].visiblePaneIds == [paneA])
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
                    ),
                visiblePaneIds: [paneA, stalePane],
                minimizedPaneIds: [stalePane]
            )
        ]

        let updated = TabArrangementRepairRules.pruningInvalidPaneIds(
            validPaneIds: [paneA],
            from: arrangements
        )

        #expect(updated[0].layout.paneIds == [paneA])
        #expect(updated[0].visiblePaneIds == [paneA])
        #expect(updated[0].minimizedPaneIds.isEmpty)
    }
}
