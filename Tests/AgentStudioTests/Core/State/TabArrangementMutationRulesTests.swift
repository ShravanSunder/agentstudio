import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct TabArrangementMutationRulesTests {
    private func activeArrangementActivePaneId(in state: TabArrangementState?) -> UUID? {
        guard let state else { return nil }
        return state.arrangements.first { $0.id == state.activeArrangementId }?.activePaneId
    }

    @Test
    func createArrangement_inheritsOnlyIncludedMinimizedPanes() {
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after, sizingMode: .halveTarget)!
            .inserting(paneId: paneC, at: paneB, direction: .horizontal, position: .after, sizingMode: .halveTarget)!
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
                .inserting(
                    paneId: paneB, at: paneA, direction: .horizontal, position: .after, sizingMode: .halveTarget)!,
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
        #expect(activeArrangementActivePaneId(in: updated) == nil)
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
                .inserting(
                    paneId: paneB, at: paneA, direction: .horizontal, position: .after, sizingMode: .halveTarget)!,
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
        #expect(activeArrangementActivePaneId(in: minimized) == paneB)
        #expect(minimized?.zoomedPaneId == nil)
        #expect(expanded?.arrangements[0].minimizedPaneIds.isEmpty == true)
        #expect(activeArrangementActivePaneId(in: expanded) == paneA)
    }

    @Test
    func breakingUpTab_returnsSinglePaneStatesInLayoutOrder() {
        let paneA = UUID()
        let paneB = UUID()
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneA)
                .inserting(
                    paneId: paneB, at: paneA, direction: .horizontal, position: .after, sizingMode: .halveTarget)!,
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
    func breakingUpTab_usesDefaultArrangementToPreserveHiddenPanes() {
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneA)
                .inserting(
                    paneId: paneB, at: paneA, direction: .horizontal, position: .after, sizingMode: .halveTarget)!
                .inserting(
                    paneId: paneC, at: paneB, direction: .horizontal, position: .after, sizingMode: .halveTarget)!,
            visiblePaneIds: [paneA, paneB, paneC]
        )
        let focusArrangement = PaneArrangement(
            name: "Focus",
            isDefault: false,
            layout: Layout(paneId: paneA)
                .inserting(
                    paneId: paneB, at: paneA, direction: .horizontal, position: .after, sizingMode: .halveTarget)!,
            visiblePaneIds: [paneA, paneB]
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [paneA, paneB, paneC],
            arrangements: [defaultArrangement, focusArrangement],
            activeArrangementId: focusArrangement.id,
            activePaneId: paneA,
            zoomedPaneId: nil
        )

        let brokenUp = TabArrangementMutationRules.breakingUpTab(state)

        #expect(brokenUp.count == 3)
        #expect(Set(brokenUp.flatMap(\.allPaneIds)) == Set([paneA, paneB, paneC]))
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
    func merging_usesSourceDefaultArrangementToPreserveHiddenPanes() {
        let sourcePaneA = UUID()
        let sourcePaneB = UUID()
        let targetPane = UUID()
        let sourceDefault = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: sourcePaneA)
                .inserting(
                    paneId: sourcePaneB, at: sourcePaneA, direction: .horizontal, position: .after,
                    sizingMode: .halveTarget)!,
            visiblePaneIds: [sourcePaneA, sourcePaneB]
        )
        let sourceFocus = PaneArrangement(
            name: "Focus",
            isDefault: false,
            layout: Layout(paneId: sourcePaneA),
            visiblePaneIds: [sourcePaneA]
        )
        let targetDefault = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: targetPane),
            visiblePaneIds: [targetPane]
        )
        let source = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [sourcePaneA, sourcePaneB],
            arrangements: [sourceDefault, sourceFocus],
            activeArrangementId: sourceFocus.id,
            activePaneId: sourcePaneA,
            zoomedPaneId: nil
        )
        let target = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [targetPane],
            arrangements: [targetDefault],
            activeArrangementId: targetDefault.id,
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

        #expect(merged?.allPaneIds == [targetPane, sourcePaneA, sourcePaneB])
        #expect(merged?.arrangements[0].layout.paneIds == [targetPane, sourcePaneA, sourcePaneB])
    }

    @Test
    func merging_before_preservesSourceOrder() {
        let sourcePaneA = UUID()
        let sourcePaneB = UUID()
        let targetPane = UUID()
        let sourceDefault = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: sourcePaneA)
                .inserting(
                    paneId: sourcePaneB, at: sourcePaneA, direction: .horizontal, position: .after,
                    sizingMode: .halveTarget)!,
            visiblePaneIds: [sourcePaneA, sourcePaneB]
        )
        let targetDefault = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: targetPane),
            visiblePaneIds: [targetPane]
        )
        let source = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [sourcePaneA, sourcePaneB],
            arrangements: [sourceDefault],
            activeArrangementId: sourceDefault.id,
            activePaneId: sourcePaneA,
            zoomedPaneId: nil
        )
        let target = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [targetPane],
            arrangements: [targetDefault],
            activeArrangementId: targetDefault.id,
            activePaneId: targetPane,
            zoomedPaneId: nil
        )

        let merged = TabArrangementMutationRules.merging(
            source: source,
            into: target,
            at: targetPane,
            direction: .horizontal,
            position: .before
        )

        #expect(merged?.arrangements[0].layout.paneIds == [sourcePaneA, sourcePaneB, targetPane])
    }

    @Test
    func merging_updatesDefaultArrangementWhenActiveArrangementIsCustom() {
        let sourcePane = UUID()
        let targetPaneA = UUID()
        let targetPaneB = UUID()
        let sourceDefault = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: sourcePane),
            visiblePaneIds: [sourcePane]
        )
        let targetDefault = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: targetPaneA)
                .inserting(
                    paneId: targetPaneB, at: targetPaneA, direction: .horizontal, position: .after,
                    sizingMode: .halveTarget)!,
            visiblePaneIds: [targetPaneA, targetPaneB]
        )
        let targetFocus = PaneArrangement(
            name: "Focus",
            isDefault: false,
            layout: Layout(paneId: targetPaneB),
            visiblePaneIds: [targetPaneB]
        )
        let source = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [sourcePane],
            arrangements: [sourceDefault],
            activeArrangementId: sourceDefault.id,
            activePaneId: sourcePane,
            zoomedPaneId: nil
        )
        let target = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [targetPaneA, targetPaneB],
            arrangements: [targetDefault, targetFocus],
            activeArrangementId: targetFocus.id,
            activePaneId: targetPaneB,
            zoomedPaneId: nil
        )

        let merged = TabArrangementMutationRules.merging(
            source: source,
            into: target,
            at: targetPaneB,
            direction: .horizontal,
            position: .after
        )

        let mergedDefault = merged?.arrangements.first(where: \.isDefault)
        let mergedActive = merged?.arrangements.first { !$0.isDefault }
        #expect(mergedDefault?.layout.contains(sourcePane) == true)
        #expect(mergedDefault?.visiblePaneIds.contains(sourcePane) == true)
        #expect(mergedActive?.layout.contains(sourcePane) == true)
    }

    @Test
    func removeArrangement_switchesToDefaultAndSkipsMinimizedFallbackPane() {
        let paneA = UUID()
        let paneB = UUID()
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneA)
                .inserting(
                    paneId: paneB, at: paneA, direction: .horizontal, position: .after, sizingMode: .halveTarget)!,
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
        #expect(activeArrangementActivePaneId(in: updated) == paneB)
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
                .inserting(
                    paneId: paneB, at: paneA, direction: .horizontal, position: .after, sizingMode: .halveTarget)!,
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
        #expect(activeArrangementActivePaneId(in: result?.updatedState) == paneA)
        #expect(result?.updatedState.zoomedPaneId == nil)
        #expect(result?.updatedState.arrangements[0].minimizedPaneIds.isEmpty == true)
        #expect(result?.extractedState.allPaneIds == [paneB])
        #expect(result?.extractedState.arrangements[0].layout.paneIds == [paneB])
    }
}
