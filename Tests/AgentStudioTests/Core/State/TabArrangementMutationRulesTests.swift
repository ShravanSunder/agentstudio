import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct TabArrangementMutationRulesTests {
    @Test
    func removeArrangement_switchesToDefaultAndSkipsMinimizedFallbackPane() {
        let paneA = UUID()
        let paneB = UUID()
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneA)
                .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after),
            visiblePaneIds: [paneA, paneB],
            minimizedPaneIds: [paneA]
        )
        let focusArrangement = PaneArrangement(
            name: "Focus",
            isDefault: false,
            layout: Layout(paneId: paneA),
            visiblePaneIds: [paneA]
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [paneA, paneB],
            arrangements: [defaultArrangement, focusArrangement],
            activeArrangementId: focusArrangement.id,
            activePaneId: paneA,
            zoomedPaneId: nil
        )

        let updated = TabArrangementMutationRules.removingArrangement(focusArrangement.id, from: state)

        #expect(updated.activeArrangementId == defaultArrangement.id)
        #expect(updated.activePaneId == paneB)
        #expect(updated.arrangements.count == 1)
    }

    @Test
    func extractingPane_returnsUpdatedSourceAndSinglePaneTabState() {
        let paneA = UUID()
        let paneB = UUID()
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneA)
                .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after),
            visiblePaneIds: [paneA, paneB],
            minimizedPaneIds: [paneB]
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [paneA, paneB],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: paneB,
            zoomedPaneId: paneB
        )

        let result = TabArrangementMutationRules.extractingPane(paneB, from: state)

        #expect(result?.updatedState.allPaneIds == [paneA])
        #expect(result?.updatedState.activePaneId == paneA)
        #expect(result?.updatedState.zoomedPaneId == nil)
        #expect(result?.updatedState.arrangements[0].minimizedPaneIds.isEmpty == true)
        #expect(result?.extractedState.allPaneIds == [paneB])
        #expect(result?.extractedState.arrangements[0].layout.paneIds == [paneB])
    }
}
