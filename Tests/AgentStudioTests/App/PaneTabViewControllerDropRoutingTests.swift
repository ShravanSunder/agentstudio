import Foundation
import Testing

@testable import AgentStudio

@Suite("PaneTabViewControllerDropRoutingTests")
struct PaneTabViewControllerDropRoutingTests {
    private func makeSnapshot(
        tabs: [TabSnapshot],
        activeTabId: UUID?,
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
    func splitDropCommitPlan_matchesPlannerDecision_forLayoutSplit() {
        let sourceTabId = UUIDv7.generate()
        let targetTabId = UUIDv7.generate()
        let sourcePaneId = UUIDv7.generate()
        let targetPaneId = UUIDv7.generate()

        let sourceTab = TabSnapshot(id: sourceTabId, paneIds: [sourcePaneId], activePaneId: sourcePaneId)
        let targetTab = TabSnapshot(id: targetTabId, paneIds: [targetPaneId], activePaneId: targetPaneId)
        let state = makeSnapshot(tabs: [sourceTab, targetTab], activeTabId: targetTabId)
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId))
        let destinationPane = makePane(id: targetPaneId)

        let plannerDecision = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: .split(
                targetPaneId: targetPaneId,
                targetTabId: targetTabId,
                direction: .right,
                targetDrawerParentPaneId: nil
            ),
            state: state
        )
        let commitPlan = PaneTabViewController.splitDropCommitPlan(
            payload: payload,
            destinationPane: destinationPane,
            destinationPaneId: targetPaneId,
            zone: .right,
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
    func splitDropCommitPlan_returnsMoveDrawerPlan_forSameDrawerParent() {
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
                    id: tabId, paneIds: [parentPaneId, sourcePaneId, destinationPaneId], activePaneId: parentPaneId)
            ],
            activeTabId: tabId,
            drawerParentByPaneId: [
                sourcePaneId: parentPaneId,
                destinationPaneId: parentPaneId,
            ]
        )
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: tabId))

        let commitPlan = PaneTabViewController.splitDropCommitPlan(
            payload: payload,
            destinationPane: destinationPane,
            destinationPaneId: destinationPaneId,
            zone: .left,
            activeTabId: tabId,
            state: state
        )

        #expect(
            commitPlan
                == .paneAction(
                    .moveDrawerPane(
                        parentPaneId: parentPaneId,
                        drawerPaneId: sourcePaneId,
                        targetDrawerPaneId: destinationPaneId,
                        direction: .left
                    )
                )
        )
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
                    paneIds: [sourceParentPaneId, destinationParentPaneId, sourcePaneId, destinationPaneId],
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

        let commitPlan = PaneTabViewController.splitDropCommitPlan(
            payload: payload,
            destinationPane: destinationPane,
            destinationPaneId: destinationPaneId,
            zone: .right,
            activeTabId: tabId,
            state: state
        )

        #expect(commitPlan == nil)
    }

    @Test
    func tabBarDropCommitPlan_matchesPlannerDecisionAcrossMatrixCases() {
        let singleSourceTabId = UUIDv7.generate()
        let multiSourceTabId = UUIDv7.generate()
        let targetTabId = UUIDv7.generate()
        let singleSourcePaneId = UUIDv7.generate()
        let multiSourcePaneId = UUIDv7.generate()
        let multiSiblingPaneId = UUIDv7.generate()
        let targetPaneId = UUIDv7.generate()
        let drawerChildPaneId = UUIDv7.generate()
        let drawerParentPaneId = UUIDv7.generate()

        let activeState = makeSnapshot(
            tabs: [
                TabSnapshot(id: singleSourceTabId, paneIds: [singleSourcePaneId], activePaneId: singleSourcePaneId),
                TabSnapshot(
                    id: multiSourceTabId,
                    paneIds: [multiSourcePaneId, multiSiblingPaneId],
                    activePaneId: multiSourcePaneId
                ),
                TabSnapshot(
                    id: targetTabId,
                    paneIds: [targetPaneId, drawerParentPaneId, drawerChildPaneId],
                    activePaneId: targetPaneId
                ),
            ],
            activeTabId: targetTabId,
            drawerParentByPaneId: [drawerChildPaneId: drawerParentPaneId]
        )
        let inactiveState = makeSnapshot(
            tabs: activeState.tabs,
            activeTabId: targetTabId,
            isManagementModeActive: false,
            drawerParentByPaneId: [drawerChildPaneId: drawerParentPaneId]
        )

        let cases: [(payload: PaneDragPayload, state: ActionStateSnapshot)] = [
            (
                PaneDragPayload(paneId: singleSourcePaneId, tabId: singleSourceTabId, drawerParentPaneId: nil),
                activeState
            ),
            (
                PaneDragPayload(paneId: multiSourcePaneId, tabId: multiSourceTabId, drawerParentPaneId: nil),
                activeState
            ),
            (
                PaneDragPayload(
                    paneId: drawerChildPaneId,
                    tabId: targetTabId,
                    drawerParentPaneId: drawerParentPaneId
                ),
                activeState
            ),
            (
                PaneDragPayload(paneId: singleSourcePaneId, tabId: singleSourceTabId, drawerParentPaneId: nil),
                inactiveState
            ),
        ]

        for testCase in cases {
            let plannerDecision = PaneDropPlanner.previewDecision(
                payload: SplitDropPayload(
                    kind: .existingPane(paneId: testCase.payload.paneId, sourceTabId: testCase.payload.tabId)
                ),
                destination: .tabBarInsertion(targetTabIndex: 1),
                state: testCase.state
            )
            let commitPlan = PaneTabViewController.tabBarDropCommitPlan(
                payload: testCase.payload,
                targetTabIndex: 1,
                state: testCase.state
            )

            if case .eligible(let expectedPlan) = plannerDecision {
                #expect(commitPlan == expectedPlan)
            } else {
                #expect(commitPlan == nil)
            }
        }
    }

    @Test
    func tabBarDropCommitPlan_returnsMoveTab_forSinglePaneSourceTab() {
        let sourceTabId = UUIDv7.generate()
        let targetTabId = UUIDv7.generate()
        let sourcePaneId = UUIDv7.generate()
        let targetPaneId = UUIDv7.generate()
        let state = makeSnapshot(
            tabs: [
                TabSnapshot(id: sourceTabId, paneIds: [sourcePaneId], activePaneId: sourcePaneId),
                TabSnapshot(id: targetTabId, paneIds: [targetPaneId], activePaneId: targetPaneId),
            ],
            activeTabId: sourceTabId
        )
        let payload = PaneDragPayload(paneId: sourcePaneId, tabId: sourceTabId, drawerParentPaneId: nil)

        let commitPlan = PaneTabViewController.tabBarDropCommitPlan(
            payload: payload,
            targetTabIndex: 1,
            state: state
        )

        #expect(commitPlan == .moveTab(tabId: sourceTabId, toIndex: 1))
    }

    @Test
    func tabBarDropCommitPlan_returnsExtractThenMove_forMultiPaneSourceTab() {
        let sourceTabId = UUIDv7.generate()
        let targetTabId = UUIDv7.generate()
        let sourcePaneId = UUIDv7.generate()
        let siblingPaneId = UUIDv7.generate()
        let targetPaneId = UUIDv7.generate()
        let state = makeSnapshot(
            tabs: [
                TabSnapshot(id: sourceTabId, paneIds: [sourcePaneId, siblingPaneId], activePaneId: sourcePaneId),
                TabSnapshot(id: targetTabId, paneIds: [targetPaneId], activePaneId: targetPaneId),
            ],
            activeTabId: sourceTabId
        )
        let payload = PaneDragPayload(paneId: sourcePaneId, tabId: sourceTabId, drawerParentPaneId: nil)

        let commitPlan = PaneTabViewController.tabBarDropCommitPlan(
            payload: payload,
            targetTabIndex: 1,
            state: state
        )

        #expect(
            commitPlan
                == .extractPaneToTabThenMove(
                    paneId: sourcePaneId,
                    sourceTabId: sourceTabId,
                    toIndex: 1
                )
        )
    }

    @Test
    func tabBarDropCommitPlan_returnsNil_forDrawerChildPayload() {
        let sourceTabId = UUIDv7.generate()
        let targetTabId = UUIDv7.generate()
        let sourcePaneId = UUIDv7.generate()
        let targetPaneId = UUIDv7.generate()
        let parentPaneId = UUIDv7.generate()
        let state = makeSnapshot(
            tabs: [
                TabSnapshot(id: sourceTabId, paneIds: [parentPaneId, sourcePaneId], activePaneId: parentPaneId),
                TabSnapshot(id: targetTabId, paneIds: [targetPaneId], activePaneId: targetPaneId),
            ],
            activeTabId: sourceTabId,
            drawerParentByPaneId: [sourcePaneId: parentPaneId]
        )
        let payload = PaneDragPayload(
            paneId: sourcePaneId,
            tabId: sourceTabId,
            drawerParentPaneId: parentPaneId
        )

        let commitPlan = PaneTabViewController.tabBarDropCommitPlan(
            payload: payload,
            targetTabIndex: 1,
            state: state
        )

        #expect(commitPlan == nil)
    }

    @Test
    func tabBarDropCommitPlan_returnsNil_whenManagementModeInactive() {
        let sourceTabId = UUIDv7.generate()
        let targetTabId = UUIDv7.generate()
        let sourcePaneId = UUIDv7.generate()
        let targetPaneId = UUIDv7.generate()
        let state = makeSnapshot(
            tabs: [
                TabSnapshot(id: sourceTabId, paneIds: [sourcePaneId], activePaneId: sourcePaneId),
                TabSnapshot(id: targetTabId, paneIds: [targetPaneId], activePaneId: targetPaneId),
            ],
            activeTabId: sourceTabId,
            isManagementModeActive: false
        )
        let payload = PaneDragPayload(paneId: sourcePaneId, tabId: sourceTabId, drawerParentPaneId: nil)

        let commitPlan = PaneTabViewController.tabBarDropCommitPlan(
            payload: payload,
            targetTabIndex: 1,
            state: state
        )

        #expect(commitPlan == nil)
    }
}
