import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class PaneDropPlannerTests {

    private func makeSnapshot(
        tabs: [TabSnapshot],
        activeTabId: UUID? = nil,
        isManagementLayerActive: Bool = true,
        drawerParentByPaneId: [UUID: UUID] = [:],
        drawerLayoutByParentPaneId: [UUID: DrawerGridLayout] = [:]
    ) -> ActionStateSnapshot {
        ActionStateSnapshot(
            tabs: tabs,
            activeTabId: activeTabId,
            isManagementLayerActive: isManagementLayerActive,
            drawerParentByPaneId: drawerParentByPaneId,
            drawerLayoutByParentPaneId: drawerLayoutByParentPaneId
        )
    }

    @Test
    func drawerPane_toTabBar_returnsIneligible() {
        let sourceTabId = UUID()
        let sourcePaneId = UUID()
        let sourceTab = TabSnapshot(
            id: sourceTabId,
            visiblePaneIds: [sourcePaneId],
            ownedPaneIds: [sourcePaneId],
            activePaneId: sourcePaneId
        )
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

        #expect(result == .ineligible(.drawerPanePayload))
    }

    @Test
    func layoutPaneSingle_toTabBar_returnsMoveTabPlan() {
        let sourceTabId = UUID()
        let sourcePaneId = UUID()
        let targetTabId = UUID()
        let sourceTab = TabSnapshot(
            id: sourceTabId,
            visiblePaneIds: [sourcePaneId],
            ownedPaneIds: [sourcePaneId],
            activePaneId: sourcePaneId
        )
        let targetTab = TabSnapshot(
            id: targetTabId,
            visiblePaneIds: [UUID()],
            ownedPaneIds: [UUID()],
            activePaneId: nil
        )
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
        let sourceTab = TabSnapshot(
            id: sourceTabId,
            visiblePaneIds: [sourcePaneA, sourcePaneB],
            ownedPaneIds: [sourcePaneA, sourcePaneB],
            activePaneId: sourcePaneA
        )
        let targetTab = TabSnapshot(
            id: targetTabId,
            visiblePaneIds: [UUID()],
            ownedPaneIds: [UUID()],
            activePaneId: nil
        )
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
    func drawerPane_sameParentDrawerSplit_returnsIneligible() {
        let sourceTabId = UUID()
        let parentPaneId = UUID()
        let sourcePaneId = UUID()
        let destinationPaneId = UUID()
        let sourceTab = TabSnapshot(
            id: sourceTabId,
            visiblePaneIds: [parentPaneId, sourcePaneId, destinationPaneId],
            ownedPaneIds: [parentPaneId, sourcePaneId, destinationPaneId],
            activePaneId: parentPaneId
        )
        let state = makeSnapshot(
            tabs: [sourceTab],
            activeTabId: sourceTabId,
            drawerParentByPaneId: [
                sourcePaneId: parentPaneId,
                destinationPaneId: parentPaneId,
            ],
            drawerLayoutByParentPaneId: [
                parentPaneId: DrawerGridLayout(topRow: Layout.autoTiled([sourcePaneId, destinationPaneId]))
            ]
        )
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId))

        let result = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .split(
                targetPaneId: destinationPaneId,
                targetTabId: sourceTabId,
                direction: .left,
                sizingMode: .halveTarget,
                targetDrawerParentPaneId: parentPaneId
            ),
            state: state
        )

        #expect(result == .ineligible(.drawerDestination))
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
            visiblePaneIds: [sourceParent, destinationParent, sourcePaneId, destinationPaneId],
            ownedPaneIds: [sourceParent, destinationParent, sourcePaneId, destinationPaneId],
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
                sizingMode: .halveTarget,
                targetDrawerParentPaneId: destinationParent
            ),
            state: state
        )

        #expect(result == .ineligible(.drawerDestination))
    }

    @Test
    func drawerPane_toMainLayoutSplit_returnsIneligible() {
        let sourceTabId = UUID()
        let parentPaneId = UUID()
        let sourcePaneId = UUID()
        let targetPaneId = UUID()
        let sourceTab = TabSnapshot(
            id: sourceTabId,
            visiblePaneIds: [parentPaneId, sourcePaneId, targetPaneId],
            ownedPaneIds: [parentPaneId, sourcePaneId, targetPaneId],
            activePaneId: parentPaneId
        )
        let state = makeSnapshot(
            tabs: [sourceTab],
            activeTabId: sourceTabId,
            drawerParentByPaneId: [sourcePaneId: parentPaneId],
            drawerLayoutByParentPaneId: [
                parentPaneId: DrawerGridLayout(topRow: Layout.autoTiled([sourcePaneId]))
            ]
        )
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId))

        let result = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .split(
                targetPaneId: targetPaneId,
                targetTabId: sourceTabId,
                direction: .right,
                sizingMode: .halveTarget,
                targetDrawerParentPaneId: nil
            ),
            state: state
        )

        #expect(result == .ineligible(.drawerPanePayload))
    }

    @Test
    func layoutPane_toSplitLayout_resolvesActionPlan() {
        let sourceTabId = UUID()
        let targetTabId = UUID()
        let sourcePaneId = UUID()
        let targetPaneId = UUID()

        let sourceTab = TabSnapshot(
            id: sourceTabId,
            visiblePaneIds: [sourcePaneId],
            ownedPaneIds: [sourcePaneId],
            activePaneId: sourcePaneId
        )
        let targetTab = TabSnapshot(
            id: targetTabId,
            visiblePaneIds: [targetPaneId],
            ownedPaneIds: [targetPaneId],
            activePaneId: targetPaneId
        )
        let state = makeSnapshot(tabs: [sourceTab, targetTab], activeTabId: targetTabId)
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId))

        let result = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .split(
                targetPaneId: targetPaneId,
                targetTabId: targetTabId,
                direction: .right,
                sizingMode: .halveTarget,
                targetDrawerParentPaneId: nil
            ),
            state: state
        )

        #expect(
            result
                == .eligible(
                    .paneAction(
                        .movePaneAcrossTabs(
                            CrossTabPaneMoveRequest(
                                paneId: sourcePaneId,
                                sourceTabId: sourceTabId,
                                destTabId: targetTabId,
                                targetPaneId: targetPaneId,
                                direction: .horizontal,
                                position: .after
                            )
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
        let targetTab = TabSnapshot(
            id: targetTabId,
            visiblePaneIds: [targetPaneId],
            ownedPaneIds: [targetPaneId],
            activePaneId: targetPaneId
        )
        let state = makeSnapshot(tabs: [targetTab], activeTabId: targetTabId)
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: missingSourceTabId))

        let result = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .split(
                targetPaneId: targetPaneId,
                targetTabId: targetTabId,
                direction: .left,
                sizingMode: .halveTarget,
                targetDrawerParentPaneId: nil
            ),
            state: state
        )

        #expect(
            result
                == .ineligible(
                    .validationFailed(
                        .sourcePaneNotFound(paneId: sourcePaneId, sourceTabId: missingSourceTabId)
                    )
                )
        )
    }

    @Test
    func destinationPaneMissing_split_returnsIneligible() {
        let sourceTabId = UUID()
        let targetTabId = UUID()
        let sourcePaneId = UUID()
        let existingTargetPaneId = UUID()
        let missingTargetPaneId = UUID()
        let sourceTab = TabSnapshot(
            id: sourceTabId,
            visiblePaneIds: [sourcePaneId],
            ownedPaneIds: [sourcePaneId],
            activePaneId: sourcePaneId
        )
        let targetTab = TabSnapshot(
            id: targetTabId,
            visiblePaneIds: [existingTargetPaneId],
            ownedPaneIds: [existingTargetPaneId],
            activePaneId: existingTargetPaneId
        )
        let state = makeSnapshot(tabs: [sourceTab, targetTab], activeTabId: targetTabId)
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId))

        let result = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .split(
                targetPaneId: missingTargetPaneId,
                targetTabId: targetTabId,
                direction: .right,
                sizingMode: .halveTarget,
                targetDrawerParentPaneId: nil
            ),
            state: state
        )

        #expect(result.isIneligible)
    }

    @Test
    func selfInsert_split_returnsIneligible() {
        let tabId = UUID()
        let paneId = UUID()
        let tab = TabSnapshot(id: tabId, visiblePaneIds: [paneId], ownedPaneIds: [paneId], activePaneId: paneId)
        let state = makeSnapshot(tabs: [tab], activeTabId: tabId)
        let payload = SplitDropPayload(kind: .existingPane(paneId: paneId, sourceTabId: tabId))

        let result = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .split(
                targetPaneId: paneId,
                targetTabId: tabId,
                direction: .left,
                sizingMode: .halveTarget,
                targetDrawerParentPaneId: nil
            ),
            state: state
        )

        #expect(result.isIneligible)
    }

    @Test
    func tabPayload_split_returnsIneligible() {
        let tabId = UUID()
        let paneA = UUID()
        let paneB = UUID()
        let tab = TabSnapshot(
            id: tabId,
            visiblePaneIds: [paneA, paneB],
            ownedPaneIds: [paneA, paneB],
            activePaneId: paneA
        )
        let state = makeSnapshot(tabs: [tab], activeTabId: tabId)
        let payload = SplitDropPayload(kind: .existingTab(tabId: tabId))

        let result = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .split(
                targetPaneId: paneA,
                targetTabId: tabId,
                direction: .right,
                sizingMode: .halveTarget,
                targetDrawerParentPaneId: nil
            ),
            state: state
        )

        #expect(result == .ineligible(.unresolvedDrop))
    }

    @Test
    func managementLayerInactive_returnsIneligible() {
        let sourceTabId = UUID()
        let targetTabId = UUID()
        let sourcePaneId = UUID()
        let targetPaneId = UUID()
        let sourceTab = TabSnapshot(
            id: sourceTabId,
            visiblePaneIds: [sourcePaneId],
            ownedPaneIds: [sourcePaneId],
            activePaneId: sourcePaneId
        )
        let targetTab = TabSnapshot(
            id: targetTabId,
            visiblePaneIds: [targetPaneId],
            ownedPaneIds: [targetPaneId],
            activePaneId: targetPaneId
        )
        let state = makeSnapshot(
            tabs: [sourceTab, targetTab],
            activeTabId: targetTabId,
            isManagementLayerActive: false
        )
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId))

        let splitResult = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .split(
                targetPaneId: targetPaneId,
                targetTabId: targetTabId,
                direction: .right,
                sizingMode: .halveTarget,
                targetDrawerParentPaneId: nil
            ),
            state: state
        )
        let tabResult = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .tabBarInsertion(targetTabIndex: 1),
            state: state
        )

        #expect(splitResult.isIneligible)
        #expect(tabResult.isIneligible)
    }
}

extension PaneDropPreviewDecision {
    fileprivate var isIneligible: Bool {
        if case .ineligible = self {
            return true
        }
        return false
    }
}
