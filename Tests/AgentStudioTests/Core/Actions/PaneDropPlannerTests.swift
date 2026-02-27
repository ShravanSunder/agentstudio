import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class PaneDropPlannerTests {

    private func makeSnapshot(
        tabs: [TabSnapshot],
        activeTabId: UUID? = nil,
        isManagementModeActive: Bool = true,
        drawerParentByPaneId: [UUID: UUID] = [:]
    ) -> ActionStateSnapshot {
        ActionStateSnapshot(
            tabs: tabs,
            activeTabId: activeTabId,
            isManagementModeActive: isManagementModeActive,
            drawerParentByPaneId: drawerParentByPaneId
        )
    }

    @Test
    func drawerPane_toTabBar_returnsIneligible() {
        let sourceTabId = UUID()
        let sourcePaneId = UUID()
        let sourceTab = TabSnapshot(id: sourceTabId, paneIds: [sourcePaneId], activePaneId: sourcePaneId)
        let state = makeSnapshot(
            tabs: [sourceTab],
            activeTabId: sourceTabId,
            drawerParentByPaneId: [sourcePaneId: UUID()]
        )
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId))

        let result = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .tabBarInsertion(targetTabIndex: 0),
            state: state
        )

        #expect(result == .ineligible)
    }

    @Test
    func layoutPaneSingle_toTabBar_returnsMoveTabPlan() {
        let sourceTabId = UUID()
        let sourcePaneId = UUID()
        let targetTabId = UUID()
        let sourceTab = TabSnapshot(id: sourceTabId, paneIds: [sourcePaneId], activePaneId: sourcePaneId)
        let targetTab = TabSnapshot(id: targetTabId, paneIds: [UUID()], activePaneId: nil)
        let state = makeSnapshot(tabs: [sourceTab, targetTab], activeTabId: sourceTabId)
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId))

        let result = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .tabBarInsertion(targetTabIndex: 1),
            state: state
        )

        #expect(result == .eligible(.moveTab(tabId: sourceTabId, toIndex: 1)))
    }

    @Test
    func layoutPaneMulti_toTabBar_returnsExtractThenMovePlan() {
        let sourceTabId = UUID()
        let sourcePaneA = UUID()
        let sourcePaneB = UUID()
        let targetTabId = UUID()
        let sourceTab = TabSnapshot(id: sourceTabId, paneIds: [sourcePaneA, sourcePaneB], activePaneId: sourcePaneA)
        let targetTab = TabSnapshot(id: targetTabId, paneIds: [UUID()], activePaneId: nil)
        let state = makeSnapshot(tabs: [sourceTab, targetTab], activeTabId: sourceTabId)
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneA, sourceTabId: sourceTabId))

        let result = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .tabBarInsertion(targetTabIndex: 1),
            state: state
        )

        #expect(
            result
                == .eligible(
                    .extractPaneToTabThenMove(
                        paneId: sourcePaneA,
                        sourceTabId: sourceTabId,
                        toIndex: 1
                    )
                )
        )
    }

    @Test
    func drawerPane_sameParentDrawerSplit_returnsMoveDrawerPlan() {
        let sourceTabId = UUID()
        let parentPaneId = UUID()
        let sourcePaneId = UUID()
        let destinationPaneId = UUID()
        let sourceTab = TabSnapshot(
            id: sourceTabId,
            paneIds: [parentPaneId, sourcePaneId, destinationPaneId],
            activePaneId: parentPaneId
        )
        let state = makeSnapshot(
            tabs: [sourceTab],
            activeTabId: sourceTabId,
            drawerParentByPaneId: [
                sourcePaneId: parentPaneId,
                destinationPaneId: parentPaneId,
            ]
        )
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId))

        let result = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .split(
                targetPaneId: destinationPaneId,
                targetTabId: sourceTabId,
                direction: .left,
                targetDrawerParentPaneId: parentPaneId
            ),
            state: state
        )

        #expect(
            result
                == .eligible(
                    .paneAction(
                        .moveDrawerPane(
                            parentPaneId: parentPaneId,
                            drawerPaneId: sourcePaneId,
                            targetDrawerPaneId: destinationPaneId,
                            direction: .left
                        )
                    )
                )
        )
    }

    @Test
    func drawerPane_crossParentDrawerSplit_returnsIneligible() {
        let sourceTabId = UUID()
        let sourceParent = UUID()
        let destinationParent = UUID()
        let sourcePaneId = UUID()
        let destinationPaneId = UUID()
        let sourceTab = TabSnapshot(
            id: sourceTabId,
            paneIds: [sourceParent, destinationParent, sourcePaneId, destinationPaneId],
            activePaneId: sourceParent
        )
        let state = makeSnapshot(
            tabs: [sourceTab],
            activeTabId: sourceTabId,
            drawerParentByPaneId: [
                sourcePaneId: sourceParent,
                destinationPaneId: destinationParent,
            ]
        )
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId))

        let result = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .split(
                targetPaneId: destinationPaneId,
                targetTabId: sourceTabId,
                direction: .right,
                targetDrawerParentPaneId: destinationParent
            ),
            state: state
        )

        #expect(result == .ineligible)
    }

    @Test
    func layoutPane_toSplitLayout_resolvesActionPlan() {
        let sourceTabId = UUID()
        let targetTabId = UUID()
        let sourcePaneId = UUID()
        let targetPaneId = UUID()

        let sourceTab = TabSnapshot(id: sourceTabId, paneIds: [sourcePaneId], activePaneId: sourcePaneId)
        let targetTab = TabSnapshot(id: targetTabId, paneIds: [targetPaneId], activePaneId: targetPaneId)
        let state = makeSnapshot(tabs: [sourceTab, targetTab], activeTabId: targetTabId)
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId))

        let result = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .split(
                targetPaneId: targetPaneId,
                targetTabId: targetTabId,
                direction: .right,
                targetDrawerParentPaneId: nil
            ),
            state: state
        )

        #expect(
            result
                == .eligible(
                    .paneAction(
                        .insertPane(
                            source: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId),
                            targetTabId: targetTabId,
                            targetPaneId: targetPaneId,
                            direction: .right
                        )
                    )
                )
        )
    }

    @Test
    func sourceTabMissing_split_returnsIneligible() {
        let targetTabId = UUID()
        let targetPaneId = UUID()
        let missingSourceTabId = UUID()
        let sourcePaneId = UUID()
        let targetTab = TabSnapshot(id: targetTabId, paneIds: [targetPaneId], activePaneId: targetPaneId)
        let state = makeSnapshot(tabs: [targetTab], activeTabId: targetTabId)
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: missingSourceTabId))

        let result = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .split(
                targetPaneId: targetPaneId,
                targetTabId: targetTabId,
                direction: .left,
                targetDrawerParentPaneId: nil
            ),
            state: state
        )

        #expect(result == .ineligible)
    }

    @Test
    func destinationPaneMissing_split_returnsIneligible() {
        let sourceTabId = UUID()
        let targetTabId = UUID()
        let sourcePaneId = UUID()
        let existingTargetPaneId = UUID()
        let missingTargetPaneId = UUID()
        let sourceTab = TabSnapshot(id: sourceTabId, paneIds: [sourcePaneId], activePaneId: sourcePaneId)
        let targetTab = TabSnapshot(
            id: targetTabId, paneIds: [existingTargetPaneId], activePaneId: existingTargetPaneId)
        let state = makeSnapshot(tabs: [sourceTab, targetTab], activeTabId: targetTabId)
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId))

        let result = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .split(
                targetPaneId: missingTargetPaneId,
                targetTabId: targetTabId,
                direction: .right,
                targetDrawerParentPaneId: nil
            ),
            state: state
        )

        #expect(result == .ineligible)
    }

    @Test
    func selfInsert_split_returnsIneligible() {
        let tabId = UUID()
        let paneId = UUID()
        let tab = TabSnapshot(id: tabId, paneIds: [paneId], activePaneId: paneId)
        let state = makeSnapshot(tabs: [tab], activeTabId: tabId)
        let payload = SplitDropPayload(kind: .existingPane(paneId: paneId, sourceTabId: tabId))

        let result = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .split(
                targetPaneId: paneId,
                targetTabId: tabId,
                direction: .left,
                targetDrawerParentPaneId: nil
            ),
            state: state
        )

        #expect(result == .ineligible)
    }

    @Test
    func selfMerge_split_returnsIneligible() {
        let tabId = UUID()
        let paneA = UUID()
        let paneB = UUID()
        let tab = TabSnapshot(id: tabId, paneIds: [paneA, paneB], activePaneId: paneA)
        let state = makeSnapshot(tabs: [tab], activeTabId: tabId)
        let payload = SplitDropPayload(kind: .existingTab(tabId: tabId))

        let result = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .split(
                targetPaneId: paneA,
                targetTabId: tabId,
                direction: .right,
                targetDrawerParentPaneId: nil
            ),
            state: state
        )

        #expect(result == .ineligible)
    }

    @Test
    func managementModeInactive_returnsIneligible() {
        let sourceTabId = UUID()
        let targetTabId = UUID()
        let sourcePaneId = UUID()
        let targetPaneId = UUID()
        let sourceTab = TabSnapshot(id: sourceTabId, paneIds: [sourcePaneId], activePaneId: sourcePaneId)
        let targetTab = TabSnapshot(id: targetTabId, paneIds: [targetPaneId], activePaneId: targetPaneId)
        let state = makeSnapshot(
            tabs: [sourceTab, targetTab],
            activeTabId: targetTabId,
            isManagementModeActive: false
        )
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId))

        let splitResult = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .split(
                targetPaneId: targetPaneId,
                targetTabId: targetTabId,
                direction: .right,
                targetDrawerParentPaneId: nil
            ),
            state: state
        )
        let tabResult = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .tabBarInsertion(targetTabIndex: 1),
            state: state
        )

        #expect(splitResult == .ineligible)
        #expect(tabResult == .ineligible)
    }
}
