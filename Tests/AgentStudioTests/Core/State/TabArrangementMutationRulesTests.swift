import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@Suite(.serialized)
struct TabArrangementMutationRulesTests {
    private func activeArrangementActivePaneId(in state: TabArrangementState?) -> UUID? {
        guard let state else { return nil }
        return state.arrangements.first { $0.id == state.activeArrangementId }?.activePaneId
    }

    @Test
    func createArrangement_inheritsCompleteUserLayoutAndMinimizedPanes() {
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after, sizingMode: .halveTarget)!
            .inserting(paneId: paneC, at: paneB, direction: .horizontal, position: .after, sizingMode: .halveTarget)!
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: layout
        )
        let userLayout = PaneArrangement(
            name: "Layout 1",
            isDefault: false,
            layout: layout,
            minimizedPaneIds: [paneB, paneC]
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [paneA, paneB, paneC],
            arrangements: [defaultArrangement, userLayout],
            activeArrangementId: userLayout.id,
            activePaneId: paneA,
        )

        let created = TabArrangementMutationRules.createArrangement(
            name: "#1",
            from: state
        )

        #expect(created?.layout == layout)
        #expect(created?.minimizedPaneIds == Set([paneB, paneC]))
    }

    @Test
    func removingUserPane_removesDrawerChildFromDrawerViews() {
        let parentPane = UUID()
        let drawerPaneA = UUID()
        let drawerPaneB = UUID()
        let drawerId = UUID()
        let drawerLayout = DrawerGridLayout(
            topRow: Layout(paneId: drawerPaneA)
                .inserting(
                    paneId: drawerPaneB,
                    at: drawerPaneA,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )!)
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: parentPane),
            drawerViews: [
                drawerId: DrawerView(
                    layout: drawerLayout,
                    activeChildId: drawerPaneB,
                    minimizedPaneIds: [drawerPaneB]
                )
            ]
        )

        let updated = TabArrangementMutationRules.removingUserPane(
            drawerPaneB,
            from: [arrangement]
        )

        let drawerView = updated[0].drawerViews[drawerId]
        #expect(drawerView?.layout.paneIds == [drawerPaneA])
        #expect(drawerView?.activeChildId == drawerPaneA)
        #expect(drawerView?.minimizedPaneIds.isEmpty == true)
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
                    paneId: paneB, at: paneA, direction: .horizontal, position: .after, sizingMode: .halveTarget)!
        )
        let focusArrangement = PaneArrangement(
            name: "Focus",
            isDefault: false,
            layout: Layout.autoTiled([paneA, paneB]),
            minimizedPaneIds: [paneA, paneB]
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [paneA, paneB],
            arrangements: [defaultArrangement, focusArrangement],
            activeArrangementId: defaultArrangement.id,
            activePaneId: paneA,
        )

        let updated = TabArrangementMutationRules.switchingArrangement(to: focusArrangement.id, in: state)

        #expect(updated.activeArrangementId == focusArrangement.id)
        #expect(activeArrangementActivePaneId(in: updated) == nil)
    }

    @Test
    func minimizingPane_fromDefaultCreatesAndActivatesUserLayout() throws {
        let paneA = UUID()
        let paneB = UUID()
        let defaultLayout = Layout(paneId: paneA)
            .inserting(
                paneId: paneB, at: paneA, direction: .horizontal, position: .after, sizingMode: .halveTarget)!
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: defaultLayout,
            activePaneId: paneA
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [paneA, paneB],
            arrangements: [defaultArrangement],
            activeArrangementId: defaultArrangement.id,
            activePaneId: paneA,
        )

        let updated = try #require(TabArrangementMutationRules.minimizingPane(paneA, in: state))
        let defaultAfterHide = try #require(updated.arrangements.first(where: { $0.isDefault }))
        let userLayout = try #require(updated.arrangements.first(where: { !$0.isDefault }))

        #expect(updated.arrangements.count == 2)
        #expect(updated.activeArrangementId == userLayout.id)
        #expect(defaultAfterHide.layout == defaultLayout)
        #expect(defaultAfterHide.minimizedPaneIds.isEmpty)
        #expect(defaultAfterHide.activePaneId == paneA)
        #expect(userLayout.name == "Layout 1")
        #expect(userLayout.layout == defaultLayout)
        #expect(userLayout.minimizedPaneIds == Set([paneA]))
        #expect(userLayout.activePaneId == paneB)
    }

    @Test
    func minimizingPane_fromDefaultUsesFirstAvailableLayoutName() throws {
        let paneA = UUID()
        let paneB = UUID()
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout.autoTiled([paneA, paneB])
        )
        let layout1 = PaneArrangement(
            name: "Layout 1",
            isDefault: false,
            layout: Layout.autoTiled([paneA, paneB])
        )
        let layout3 = PaneArrangement(
            name: "Layout 3",
            isDefault: false,
            layout: Layout.autoTiled([paneA, paneB])
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [paneA, paneB],
            arrangements: [defaultArrangement, layout1, layout3],
            activeArrangementId: defaultArrangement.id,
            activePaneId: paneA,
        )

        let updated = try #require(TabArrangementMutationRules.minimizingPane(paneB, in: state))

        #expect(updated.arrangements.map(\.name) == ["Default", "Layout 1", "Layout 3", "Layout 2"])
        #expect(updated.arrangements.last?.minimizedPaneIds == Set([paneB]))
    }

    @Test
    func minimizingPane_whenDefaultCannotBeClonedPublishesNoMutation() {
        let paneA = UUID()
        let malformedDefault = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneA)
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [],
            arrangements: [malformedDefault],
            activeArrangementId: malformedDefault.id,
            activePaneId: paneA,
        )

        let updated = TabArrangementMutationRules.minimizingPane(paneA, in: state)

        #expect(updated == nil)
        #expect(state.arrangements == [malformedDefault])
        #expect(state.activeArrangementId == malformedDefault.id)
    }

    @Test
    func minimizingPane_inUserLayoutUpdatesThatLayoutDirectly() throws {
        let paneA = UUID()
        let paneB = UUID()
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout.autoTiled([paneA, paneB])
        )
        let userLayout = PaneArrangement(
            name: "Layout 1",
            isDefault: false,
            layout: Layout.autoTiled([paneA, paneB]),
            activePaneId: paneA
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [paneA, paneB],
            arrangements: [defaultArrangement, userLayout],
            activeArrangementId: userLayout.id,
            activePaneId: paneA,
        )

        let minimized = try #require(TabArrangementMutationRules.minimizingPane(paneA, in: state))
        let expanded = TabArrangementMutationRules.expandingPane(paneA, in: minimized)

        #expect(minimized.arrangements.count == 2)
        #expect(minimized.arrangements[0] == defaultArrangement)
        #expect(minimized.arrangements[1].minimizedPaneIds == Set([paneA]))
        #expect(activeArrangementActivePaneId(in: minimized) == paneB)
        #expect(expanded.arrangements[1].minimizedPaneIds.isEmpty)
        #expect(activeArrangementActivePaneId(in: expanded) == paneA)
    }

    @Test
    func minimizingPane_doesNotTreatDrawerChildAsMainPane() {
        let parentPane = UUID()
        let drawerPane = UUID()
        let drawerId = UUID()
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: parentPane),
            drawerViews: [
                drawerId: DrawerView(
                    layout: DrawerGridLayout(topRow: Layout(paneId: drawerPane))
                )
            ]
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [parentPane, drawerPane],
            arrangements: [defaultArrangement],
            activeArrangementId: defaultArrangement.id,
            activePaneId: parentPane,
        )

        let updated = TabArrangementMutationRules.minimizingPane(drawerPane, in: state)

        #expect(updated == nil)
        #expect(state.arrangements == [defaultArrangement])
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
                    paneId: paneB, at: paneA, direction: .horizontal, position: .after, sizingMode: .halveTarget)!
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [paneA, paneB],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: paneA,
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
                    paneId: paneC, at: paneB, direction: .horizontal, position: .after, sizingMode: .halveTarget)!
        )
        let focusArrangement = PaneArrangement(
            name: "Focus",
            isDefault: false,
            layout: Layout.autoTiled([paneC, paneA, paneB])
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [paneA, paneB, paneC],
            arrangements: [defaultArrangement, focusArrangement],
            activeArrangementId: focusArrangement.id,
            activePaneId: paneA,
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
            layout: Layout(paneId: sourcePane)
        )
        let targetArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: targetPane)
        )
        let source = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [sourcePane],
            arrangements: [sourceArrangement],
            activeArrangementId: sourceArrangement.id,
            activePaneId: sourcePane,
        )
        let target = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [targetPane],
            arrangements: [targetArrangement],
            activeArrangementId: targetArrangement.id,
            activePaneId: targetPane,
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
                    sizingMode: .halveTarget)!
        )
        let sourceFocus = PaneArrangement(
            name: "Focus",
            isDefault: false,
            layout: Layout.autoTiled([sourcePaneB, sourcePaneA])
        )
        let targetDefault = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: targetPane)
        )
        let source = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [sourcePaneA, sourcePaneB],
            arrangements: [sourceDefault, sourceFocus],
            activeArrangementId: sourceFocus.id,
            activePaneId: sourcePaneA,
        )
        let target = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [targetPane],
            arrangements: [targetDefault],
            activeArrangementId: targetDefault.id,
            activePaneId: targetPane,
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
                    sizingMode: .halveTarget)!
        )
        let targetDefault = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: targetPane)
        )
        let source = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [sourcePaneA, sourcePaneB],
            arrangements: [sourceDefault],
            activeArrangementId: sourceDefault.id,
            activePaneId: sourcePaneA,
        )
        let target = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [targetPane],
            arrangements: [targetDefault],
            activeArrangementId: targetDefault.id,
            activePaneId: targetPane,
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
            layout: Layout(paneId: sourcePane)
        )
        let targetDefault = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: targetPaneA)
                .inserting(
                    paneId: targetPaneB, at: targetPaneA, direction: .horizontal, position: .after,
                    sizingMode: .halveTarget)!
        )
        let targetFocus = PaneArrangement(
            name: "Focus",
            isDefault: false,
            layout: Layout.autoTiled([targetPaneB, targetPaneA])
        )
        let source = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [sourcePane],
            arrangements: [sourceDefault],
            activeArrangementId: sourceDefault.id,
            activePaneId: sourcePane,
        )
        let target = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [targetPaneA, targetPaneB],
            arrangements: [targetDefault, targetFocus],
            activeArrangementId: targetFocus.id,
            activePaneId: targetPaneB,
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
        #expect(mergedActive?.layout.contains(sourcePane) == true)
    }

    @Test
    func merging_appendsSourcePanesToEveryTargetArrangement() {
        let sourcePane = UUID()
        let targetPaneA = UUID()
        let targetPaneB = UUID()
        let sourceDefault = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: sourcePane)
        )
        let targetDefault = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: targetPaneA)
                .inserting(
                    paneId: targetPaneB, at: targetPaneA, direction: .horizontal, position: .after,
                    sizingMode: .halveTarget)!
        )
        let targetFocus = PaneArrangement(
            name: "Focus",
            isDefault: false,
            layout: Layout.autoTiled([targetPaneB, targetPaneA])
        )
        let targetReview = PaneArrangement(
            name: "Review",
            isDefault: false,
            layout: Layout.autoTiled([targetPaneA, targetPaneB])
        )
        let source = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [sourcePane],
            arrangements: [sourceDefault],
            activeArrangementId: sourceDefault.id,
            activePaneId: sourcePane,
        )
        let target = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [targetPaneA, targetPaneB],
            arrangements: [targetDefault, targetFocus, targetReview],
            activeArrangementId: targetFocus.id,
            activePaneId: targetPaneB,
        )

        let merged = TabArrangementMutationRules.merging(
            source: source,
            into: target,
            at: targetPaneB,
            direction: .horizontal,
            position: .after
        )

        #expect(merged?.arrangements.allSatisfy { $0.layout.contains(sourcePane) } == true)
    }

    @Test
    func removeArrangement_switchesToVisibilityCompleteDefault() {
        let paneA = UUID()
        let paneB = UUID()
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneA)
                .inserting(
                    paneId: paneB, at: paneA, direction: .horizontal, position: .after, sizingMode: .halveTarget)!,
        )
        let userLayout = PaneArrangement(
            name: "Layout 1",
            isDefault: false,
            layout: Layout.autoTiled([paneB, paneA])
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [paneA, paneB],
            arrangements: [defaultArrangement, userLayout],
            activeArrangementId: userLayout.id,
            activePaneId: paneA,
        )

        let updated = TabArrangementMutationRules.removingArrangement(userLayout.id, from: state)

        #expect(updated.activeArrangementId == defaultArrangement.id)
        #expect(activeArrangementActivePaneId(in: updated) == paneA)
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
            minimizedPaneIds: [paneB]
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [paneA, paneB],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: paneB,
        )

        let result = TabArrangementMutationRules.extractingPane(paneB, from: state)

        #expect(result?.updatedState.allPaneIds == [paneA])
        #expect(activeArrangementActivePaneId(in: result?.updatedState) == paneA)
        #expect(result?.updatedState.arrangements[0].minimizedPaneIds.isEmpty == true)
        #expect(result?.extractedState.allPaneIds == [paneB])
        #expect(result?.extractedState.arrangements[0].layout.paneIds == [paneB])
    }
}
