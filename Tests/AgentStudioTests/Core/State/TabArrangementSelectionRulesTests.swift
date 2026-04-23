import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct TabArrangementSelectionRulesTests {
    @Test
    func firstUnminimizedPaneId_returnsFirstVisibleNonMinimizedPane() {
        let paneA = UUID()
        let paneB = UUID()
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneA)
                .inserting(
                    paneId: paneB, at: paneA, direction: .horizontal, position: .after, sizingMode: .halveTarget),
            visiblePaneIds: [paneA, paneB],
            minimizedPaneIds: [paneA]
        )

        let resolved = TabArrangementSelectionRules.firstUnminimizedPaneId(in: arrangement)

        #expect(resolved == paneB)
    }

    @Test
    func firstUnminimizedPaneId_returnsNilWhenAllVisiblePanesAreMinimized() {
        let paneA = UUID()
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneA),
            visiblePaneIds: [paneA],
            minimizedPaneIds: [paneA]
        )

        let resolved = TabArrangementSelectionRules.firstUnminimizedPaneId(in: arrangement)

        #expect(resolved == nil)
    }

    @Test
    func fallbackActivePaneId_returnsCurrentPaneWhenStillVisibleAndUnminimized() {
        let paneA = UUID()
        let paneB = UUID()
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneA)
                .inserting(
                    paneId: paneB, at: paneA, direction: .horizontal, position: .after, sizingMode: .halveTarget),
            visiblePaneIds: [paneA, paneB]
        )

        let resolved = TabArrangementSelectionRules.fallbackActivePaneId(
            currentActivePaneId: paneB,
            in: arrangement
        )

        #expect(resolved == paneB)
    }

    @Test
    func fallbackActivePaneId_returnsFirstUnminimizedPaneWhenCurrentPaneIsMinimized() {
        let paneA = UUID()
        let paneB = UUID()
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneA)
                .inserting(
                    paneId: paneB, at: paneA, direction: .horizontal, position: .after, sizingMode: .halveTarget),
            visiblePaneIds: [paneA, paneB],
            minimizedPaneIds: [paneB]
        )

        let resolved = TabArrangementSelectionRules.fallbackActivePaneId(
            currentActivePaneId: paneB,
            in: arrangement
        )

        #expect(resolved == paneA)
    }

    @Test
    func fallbackActivePaneId_returnsNilWhenAllPanesAreMinimized() {
        let paneA = UUID()
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneA),
            visiblePaneIds: [paneA],
            minimizedPaneIds: [paneA]
        )

        let resolved = TabArrangementSelectionRules.fallbackActivePaneId(
            currentActivePaneId: paneA,
            in: arrangement
        )

        #expect(resolved == nil)
    }
}
