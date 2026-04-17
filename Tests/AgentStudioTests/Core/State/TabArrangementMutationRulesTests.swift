import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct TabArrangementMutationRulesTests {
    @Test
    func createArrangement_inheritsOnlyIncludedMinimizedPanes() {
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)
            .inserting(paneId: paneC, at: paneB, direction: .horizontal, position: .after)
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: layout,
            visiblePaneIds: [paneA, paneB, paneC],
            minimizedPaneIds: [paneB, paneC]
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [paneA, paneB, paneC],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: paneA,
            zoomedPaneId: nil
        )

        let created = TabArrangementMutationRules.createArrangement(
            name: "#1",
            paneIds: [paneA, paneB],
            from: state
        )

        #expect(created?.visiblePaneIds == Set([paneA, paneB]))
        #expect(created?.minimizedPaneIds == Set([paneB]))
    }

    @Test
    func switchingArrangement_replacesInvalidOrMinimizedActivePane() {
        let paneA = UUID()
        let paneB = UUID()
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneA)
                .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after),
            visiblePaneIds: [paneA, paneB]
        )
        let focusArrangement = PaneArrangement(
            name: "Focus",
            isDefault: false,
            layout: Layout(paneId: paneB),
            visiblePaneIds: [paneB],
            minimizedPaneIds: [paneB]
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [paneA, paneB],
            arrangements: [defaultArrangement, focusArrangement],
            activeArrangementId: defaultArrangement.id,
            activePaneId: paneA,
            zoomedPaneId: paneA
        )

        let updated = TabArrangementMutationRules.switchingArrangement(to: focusArrangement.id, in: state)

        #expect(updated.activeArrangementId == focusArrangement.id)
        #expect(updated.activePaneId == nil)
        #expect(updated.zoomedPaneId == nil)
    }

    @Test
    func minimizingAndExpandingPane_updatesActivePaneAndMinimizedSet() {
        let paneA = UUID()
        let paneB = UUID()
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneA)
                .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after),
            visiblePaneIds: [paneA, paneB]
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [paneA, paneB],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: paneA,
            zoomedPaneId: paneA
        )

        let minimized = TabArrangementMutationRules.minimizingPane(paneA, in: state)
        let expanded = minimized.map { TabArrangementMutationRules.expandingPane(paneA, in: $0) }

        #expect(minimized?.arrangements[0].minimizedPaneIds == Set([paneA]))
        #expect(minimized?.activePaneId == paneB)
        #expect(minimized?.zoomedPaneId == nil)
        #expect(expanded?.arrangements[0].minimizedPaneIds.isEmpty == true)
        #expect(expanded?.activePaneId == paneA)
    }

    @Test
    func breakingUpTab_returnsSinglePaneStatesInLayoutOrder() {
        let paneA = UUID()
        let paneB = UUID()
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneA)
                .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after),
            visiblePaneIds: [paneA, paneB]
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [paneA, paneB],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: paneA,
            zoomedPaneId: nil
        )

        let brokenUp = TabArrangementMutationRules.breakingUpTab(state)

        #expect(brokenUp.count == 2)
        #expect(brokenUp.map { $0.allPaneIds.first! } == [paneA, paneB])
    }

    @Test
    func merging_appendsSourceLayoutIntoTargetArrangement() {
        let sourcePane = UUID()
        let targetPane = UUID()
        let sourceArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: sourcePane),
            visiblePaneIds: [sourcePane]
        )
        let targetArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: targetPane),
            visiblePaneIds: [targetPane]
        )
        let source = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [sourcePane],
            arrangements: [sourceArrangement],
            activeArrangementId: sourceArrangement.id,
            activePaneId: sourcePane,
            zoomedPaneId: nil
        )
        let target = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [targetPane],
            arrangements: [targetArrangement],
            activeArrangementId: targetArrangement.id,
            activePaneId: targetPane,
            zoomedPaneId: nil
        )

        let merged = TabArrangementMutationRules.merging(
            source: source,
            into: target,
            at: targetPane,
            direction: .horizontal,
            position: .after
        )

        #expect(merged?.allPaneIds == [targetPane, sourcePane])
        #expect(merged?.arrangements[0].layout.paneIds == [targetPane, sourcePane])
    }

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
