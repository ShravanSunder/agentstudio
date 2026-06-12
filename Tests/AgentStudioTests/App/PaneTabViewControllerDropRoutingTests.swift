import Foundation
import Testing

@testable import AgentStudio

@Suite("PaneTabViewControllerDropRoutingTests")
struct PaneTabViewControllerDropRoutingTests {
    private func makeSnapshot(
        tabs: [TabSnapshot],
        activeTabId: UUID?,
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
    func splitDropCommitPlan_matchesPlannerDecision_forLayoutSplit() {
        let sourceTabId = UUIDv7.generate()
        let targetTabId = UUIDv7.generate()
        let sourcePaneId = UUIDv7.generate()
        let targetPaneId = UUIDv7.generate()

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
        let destinationPane = makePane(id: targetPaneId)

        let plannerDecision = PaneDropPlanner.previewDecision(
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
        let commitPlan = SplitDropInteractionController.splitDropCommitPlan(
            payload: payload,
            destination: SplitDropCommitDestination(
                paneId: targetPaneId,
                drawerParentPaneId: destinationPane.parentPaneId
            ),
            zone: .right,
            sizingMode: .halveTarget,
            activeTabId: targetTabId,
            state: state
        )

        if case .eligible(let expectedPlan) = plannerDecision {
            #expect(commitPlan == expectedPlan)
        } else {
            #expect(commitPlan == nil)
        }
    }

    @Test
    func splitDropCommitPlan_returnsNil_forSameDrawerParentDrawerMove() {
        let parentPaneId = UUIDv7.generate()
        let sourcePaneId = UUIDv7.generate()
        let destinationPaneId = UUIDv7.generate()
        let tabId = UUIDv7.generate()

        var sourcePane = makePane(id: sourcePaneId)
        sourcePane.kind = .drawerChild(parentPaneId: parentPaneId)

        var destinationPane = makePane(id: destinationPaneId)
        destinationPane.kind = .drawerChild(parentPaneId: parentPaneId)

        let state = makeSnapshot(
            tabs: [
                TabSnapshot(
                    id: tabId,
                    visiblePaneIds: [parentPaneId, sourcePaneId, destinationPaneId],
                    ownedPaneIds: [parentPaneId, sourcePaneId, destinationPaneId],
                    activePaneId: parentPaneId
                )
            ],
            activeTabId: tabId,
            drawerParentByPaneId: [
                sourcePaneId: parentPaneId,
                destinationPaneId: parentPaneId,
            ],
            drawerLayoutByParentPaneId: [
                parentPaneId: DrawerGridLayout(topRow: Layout.autoTiled([sourcePaneId, destinationPaneId]))
            ]
        )
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: tabId))

        let commitPlan = SplitDropInteractionController.splitDropCommitPlan(
            payload: payload,
            destination: SplitDropCommitDestination(
                paneId: destinationPaneId,
                drawerParentPaneId: destinationPane.parentPaneId
            ),
            zone: .left,
            sizingMode: .halveTarget,
            activeTabId: tabId,
            state: state
        )

        #expect(commitPlan == nil)
    }

    @Test
    func splitDropCommitPlan_returnsNil_forCrossParentDrawerMove() {
        let sourceParentPaneId = UUIDv7.generate()
        let destinationParentPaneId = UUIDv7.generate()
        let sourcePaneId = UUIDv7.generate()
        let destinationPaneId = UUIDv7.generate()
        let tabId = UUIDv7.generate()

        var sourcePane = makePane(id: sourcePaneId)
        sourcePane.kind = .drawerChild(parentPaneId: sourceParentPaneId)

        var destinationPane = makePane(id: destinationPaneId)
        destinationPane.kind = .drawerChild(parentPaneId: destinationParentPaneId)

        let state = makeSnapshot(
            tabs: [
                TabSnapshot(
                    id: tabId,
                    visiblePaneIds: [sourceParentPaneId, destinationParentPaneId, sourcePaneId, destinationPaneId],
                    ownedPaneIds: [sourceParentPaneId, destinationParentPaneId, sourcePaneId, destinationPaneId],
                    activePaneId: sourceParentPaneId
                )
            ],
            activeTabId: tabId,
            drawerParentByPaneId: [
                sourcePaneId: sourceParentPaneId,
                destinationPaneId: destinationParentPaneId,
            ]
        )
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: tabId))

        let commitPlan = SplitDropInteractionController.splitDropCommitPlan(
            payload: payload,
            destination: SplitDropCommitDestination(
                paneId: destinationPaneId,
                drawerParentPaneId: destinationPane.parentPaneId
            ),
            zone: .right,
            sizingMode: .halveTarget,
            activeTabId: tabId,
            state: state
        )

        #expect(commitPlan == nil)
    }

    @Test
    func splitDropCommitPlan_returnsNil_forDrawerPaneToLayoutTarget() {
        let parentPaneId = UUIDv7.generate()
        let sourcePaneId = UUIDv7.generate()
        let destinationPaneId = UUIDv7.generate()
        let tabId = UUIDv7.generate()

        var sourcePane = makePane(id: sourcePaneId)
        sourcePane.kind = .drawerChild(parentPaneId: parentPaneId)
        let destinationPane = makePane(id: destinationPaneId)

        let state = makeSnapshot(
            tabs: [
                TabSnapshot(
                    id: tabId,
                    visiblePaneIds: [parentPaneId, destinationPaneId],
                    ownedPaneIds: [parentPaneId, sourcePaneId, destinationPaneId],
                    activePaneId: parentPaneId
                )
            ],
            activeTabId: tabId,
            drawerParentByPaneId: [sourcePaneId: parentPaneId],
            drawerLayoutByParentPaneId: [
                parentPaneId: DrawerGridLayout(topRow: Layout.autoTiled([sourcePaneId]))
            ]
        )
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: tabId))

        let commitPlan = SplitDropInteractionController.splitDropCommitPlan(
            payload: payload,
            destination: SplitDropCommitDestination(
                paneId: destinationPaneId,
                drawerParentPaneId: destinationPane.parentPaneId
            ),
            zone: .right,
            sizingMode: .halveTarget,
            activeTabId: tabId,
            state: state
        )

        #expect(commitPlan == nil)
    }
}
