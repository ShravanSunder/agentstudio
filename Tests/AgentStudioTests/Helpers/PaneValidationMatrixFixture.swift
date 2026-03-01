import Foundation

@testable import AgentStudio

struct PaneValidationMatrixCase: Sendable {
    let name: String
    let payload: SplitDropPayload
    let destination: PaneDropDestination
    let state: ActionStateSnapshot
    let expectedDecision: PaneDropPreviewDecision
}

enum PaneValidationMatrixFixture {
    static let cases: [PaneValidationMatrixCase] = [
        layoutSinglePaneToTabBarMoveTab,
        layoutMultiPaneToTabBarExtractThenMove,
        drawerChildToTabBarIneligible,
        drawerChildSameParentDrawerSplitMove,
        drawerChildDifferentParentDrawerSplitIneligible,
        drawerChildToLayoutSplitIneligible,
        layoutPaneToSplitLayoutInsert,
        existingTabToSplitLayoutMerge,
        newTerminalToSplitLayoutInsert,
        managementModeOffAlwaysIneligible,
        managementModeOffTabBarIneligible,
    ]

    private static let layoutSinglePaneToTabBarMoveTab: PaneValidationMatrixCase = {
        let sourceTabId = UUIDv7.generate()
        let targetTabId = UUIDv7.generate()
        let sourcePaneId = UUIDv7.generate()
        let targetPaneId = UUIDv7.generate()
        let state = snapshot(
            tabs: [
                TabSnapshot(id: sourceTabId, paneIds: [sourcePaneId], activePaneId: sourcePaneId),
                TabSnapshot(id: targetTabId, paneIds: [targetPaneId], activePaneId: targetPaneId),
            ],
            activeTabId: sourceTabId
        )

        return PaneValidationMatrixCase(
            name: "layout single-pane tab -> tab bar insertion",
            payload: SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId)),
            destination: .tabBarInsertion(targetTabIndex: 1),
            state: state,
            expectedDecision: .eligible(.moveTab(tabId: sourceTabId, toIndex: 1))
        )
    }()

    private static let layoutMultiPaneToTabBarExtractThenMove: PaneValidationMatrixCase = {
        let sourceTabId = UUIDv7.generate()
        let targetTabId = UUIDv7.generate()
        let sourcePaneId = UUIDv7.generate()
        let siblingPaneId = UUIDv7.generate()
        let targetPaneId = UUIDv7.generate()
        let state = snapshot(
            tabs: [
                TabSnapshot(id: sourceTabId, paneIds: [sourcePaneId, siblingPaneId], activePaneId: sourcePaneId),
                TabSnapshot(id: targetTabId, paneIds: [targetPaneId], activePaneId: targetPaneId),
            ],
            activeTabId: sourceTabId
        )

        return PaneValidationMatrixCase(
            name: "layout multi-pane tab -> tab bar insertion",
            payload: SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId)),
            destination: .tabBarInsertion(targetTabIndex: 1),
            state: state,
            expectedDecision: .eligible(
                .extractPaneToTabThenMove(
                    paneId: sourcePaneId,
                    sourceTabId: sourceTabId,
                    toIndex: 1
                )
            )
        )
    }()

    private static let drawerChildToTabBarIneligible: PaneValidationMatrixCase = {
        let sourceTabId = UUIDv7.generate()
        let targetTabId = UUIDv7.generate()
        let parentPaneId = UUIDv7.generate()
        let drawerPaneId = UUIDv7.generate()
        let targetPaneId = UUIDv7.generate()
        let state = snapshot(
            tabs: [
                TabSnapshot(id: sourceTabId, paneIds: [parentPaneId, drawerPaneId], activePaneId: parentPaneId),
                TabSnapshot(id: targetTabId, paneIds: [targetPaneId], activePaneId: targetPaneId),
            ],
            activeTabId: sourceTabId,
            drawerParentByPaneId: [drawerPaneId: parentPaneId]
        )

        return PaneValidationMatrixCase(
            name: "drawer child -> tab bar insertion",
            payload: SplitDropPayload(kind: .existingPane(paneId: drawerPaneId, sourceTabId: sourceTabId)),
            destination: .tabBarInsertion(targetTabIndex: 1),
            state: state,
            expectedDecision: .ineligible
        )
    }()

    private static let drawerChildSameParentDrawerSplitMove: PaneValidationMatrixCase = {
        let tabId = UUIDv7.generate()
        let parentPaneId = UUIDv7.generate()
        let sourceDrawerPaneId = UUIDv7.generate()
        let targetDrawerPaneId = UUIDv7.generate()
        let state = snapshot(
            tabs: [
                TabSnapshot(
                    id: tabId,
                    paneIds: [parentPaneId, sourceDrawerPaneId, targetDrawerPaneId],
                    activePaneId: parentPaneId
                )
            ],
            activeTabId: tabId,
            drawerParentByPaneId: [
                sourceDrawerPaneId: parentPaneId,
                targetDrawerPaneId: parentPaneId,
            ]
        )

        return PaneValidationMatrixCase(
            name: "drawer child same parent -> drawer split",
            payload: SplitDropPayload(kind: .existingPane(paneId: sourceDrawerPaneId, sourceTabId: tabId)),
            destination: .split(
                targetPaneId: targetDrawerPaneId,
                targetTabId: tabId,
                direction: .left,
                targetDrawerParentPaneId: parentPaneId
            ),
            state: state,
            expectedDecision: .eligible(
                .paneAction(
                    .moveDrawerPane(
                        parentPaneId: parentPaneId,
                        drawerPaneId: sourceDrawerPaneId,
                        targetDrawerPaneId: targetDrawerPaneId,
                        direction: .left
                    )
                )
            )
        )
    }()

    private static let drawerChildDifferentParentDrawerSplitIneligible: PaneValidationMatrixCase = {
        let tabId = UUIDv7.generate()
        let sourceParentPaneId = UUIDv7.generate()
        let destinationParentPaneId = UUIDv7.generate()
        let sourceDrawerPaneId = UUIDv7.generate()
        let targetDrawerPaneId = UUIDv7.generate()
        let state = snapshot(
            tabs: [
                TabSnapshot(
                    id: tabId,
                    paneIds: [sourceParentPaneId, destinationParentPaneId, sourceDrawerPaneId, targetDrawerPaneId],
                    activePaneId: sourceParentPaneId
                )
            ],
            activeTabId: tabId,
            drawerParentByPaneId: [
                sourceDrawerPaneId: sourceParentPaneId,
                targetDrawerPaneId: destinationParentPaneId,
            ]
        )

        return PaneValidationMatrixCase(
            name: "drawer child different parent -> drawer split",
            payload: SplitDropPayload(kind: .existingPane(paneId: sourceDrawerPaneId, sourceTabId: tabId)),
            destination: .split(
                targetPaneId: targetDrawerPaneId,
                targetTabId: tabId,
                direction: .right,
                targetDrawerParentPaneId: destinationParentPaneId
            ),
            state: state,
            expectedDecision: .ineligible
        )
    }()

    private static let drawerChildToLayoutSplitIneligible: PaneValidationMatrixCase = {
        let tabId = UUIDv7.generate()
        let parentPaneId = UUIDv7.generate()
        let drawerPaneId = UUIDv7.generate()
        let layoutTargetPaneId = UUIDv7.generate()
        let state = snapshot(
            tabs: [
                TabSnapshot(
                    id: tabId,
                    paneIds: [parentPaneId, drawerPaneId, layoutTargetPaneId],
                    activePaneId: parentPaneId
                )
            ],
            activeTabId: tabId,
            drawerParentByPaneId: [drawerPaneId: parentPaneId]
        )

        return PaneValidationMatrixCase(
            name: "drawer child -> layout split target (no drawer parent)",
            payload: SplitDropPayload(kind: .existingPane(paneId: drawerPaneId, sourceTabId: tabId)),
            destination: .split(
                targetPaneId: layoutTargetPaneId,
                targetTabId: tabId,
                direction: .right,
                targetDrawerParentPaneId: nil
            ),
            state: state,
            expectedDecision: .ineligible
        )
    }()

    private static let layoutPaneToSplitLayoutInsert: PaneValidationMatrixCase = {
        let sourceTabId = UUIDv7.generate()
        let targetTabId = UUIDv7.generate()
        let sourcePaneId = UUIDv7.generate()
        let targetPaneId = UUIDv7.generate()
        let state = snapshot(
            tabs: [
                TabSnapshot(id: sourceTabId, paneIds: [sourcePaneId], activePaneId: sourcePaneId),
                TabSnapshot(id: targetTabId, paneIds: [targetPaneId], activePaneId: targetPaneId),
            ],
            activeTabId: targetTabId
        )

        return PaneValidationMatrixCase(
            name: "layout pane -> split target in layout",
            payload: SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId)),
            destination: .split(
                targetPaneId: targetPaneId,
                targetTabId: targetTabId,
                direction: .right,
                targetDrawerParentPaneId: nil
            ),
            state: state,
            expectedDecision: .eligible(
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
    }()

    private static let existingTabToSplitLayoutMerge: PaneValidationMatrixCase = {
        let sourceTabId = UUIDv7.generate()
        let targetTabId = UUIDv7.generate()
        let sourcePaneA = UUIDv7.generate()
        let sourcePaneB = UUIDv7.generate()
        let targetPaneId = UUIDv7.generate()
        let state = snapshot(
            tabs: [
                TabSnapshot(id: sourceTabId, paneIds: [sourcePaneA, sourcePaneB], activePaneId: sourcePaneA),
                TabSnapshot(id: targetTabId, paneIds: [targetPaneId], activePaneId: targetPaneId),
            ],
            activeTabId: targetTabId
        )

        return PaneValidationMatrixCase(
            name: "existing tab -> split target in layout",
            payload: SplitDropPayload(kind: .existingTab(tabId: sourceTabId)),
            destination: .split(
                targetPaneId: targetPaneId,
                targetTabId: targetTabId,
                direction: .right,
                targetDrawerParentPaneId: nil
            ),
            state: state,
            expectedDecision: .eligible(
                .paneAction(
                    .mergeTab(
                        sourceTabId: sourceTabId,
                        targetTabId: targetTabId,
                        targetPaneId: targetPaneId,
                        direction: .right
                    )
                )
            )
        )
    }()

    private static let newTerminalToSplitLayoutInsert: PaneValidationMatrixCase = {
        let targetTabId = UUIDv7.generate()
        let targetPaneId = UUIDv7.generate()
        let state = snapshot(
            tabs: [
                TabSnapshot(id: targetTabId, paneIds: [targetPaneId], activePaneId: targetPaneId)
            ],
            activeTabId: targetTabId
        )

        return PaneValidationMatrixCase(
            name: "new terminal payload -> split target in layout",
            payload: SplitDropPayload(kind: .newTerminal),
            destination: .split(
                targetPaneId: targetPaneId,
                targetTabId: targetTabId,
                direction: .right,
                targetDrawerParentPaneId: nil
            ),
            state: state,
            expectedDecision: .eligible(
                .paneAction(
                    .insertPane(
                        source: .newTerminal,
                        targetTabId: targetTabId,
                        targetPaneId: targetPaneId,
                        direction: .right
                    )
                )
            )
        )
    }()

    private static let managementModeOffAlwaysIneligible: PaneValidationMatrixCase = {
        let sourceTabId = UUIDv7.generate()
        let targetTabId = UUIDv7.generate()
        let sourcePaneId = UUIDv7.generate()
        let targetPaneId = UUIDv7.generate()
        let state = snapshot(
            tabs: [
                TabSnapshot(id: sourceTabId, paneIds: [sourcePaneId], activePaneId: sourcePaneId),
                TabSnapshot(id: targetTabId, paneIds: [targetPaneId], activePaneId: targetPaneId),
            ],
            activeTabId: targetTabId,
            isManagementModeActive: false
        )

        return PaneValidationMatrixCase(
            name: "management mode off -> ineligible",
            payload: SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId)),
            destination: .split(
                targetPaneId: targetPaneId,
                targetTabId: targetTabId,
                direction: .left,
                targetDrawerParentPaneId: nil
            ),
            state: state,
            expectedDecision: .ineligible
        )
    }()

    private static let managementModeOffTabBarIneligible: PaneValidationMatrixCase = {
        let sourceTabId = UUIDv7.generate()
        let targetTabId = UUIDv7.generate()
        let sourcePaneId = UUIDv7.generate()
        let targetPaneId = UUIDv7.generate()
        let state = snapshot(
            tabs: [
                TabSnapshot(id: sourceTabId, paneIds: [sourcePaneId], activePaneId: sourcePaneId),
                TabSnapshot(id: targetTabId, paneIds: [targetPaneId], activePaneId: targetPaneId),
            ],
            activeTabId: sourceTabId,
            isManagementModeActive: false
        )

        return PaneValidationMatrixCase(
            name: "management mode off -> tab bar insertion ineligible",
            payload: SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId)),
            destination: .tabBarInsertion(targetTabIndex: 1),
            state: state,
            expectedDecision: .ineligible
        )
    }()

    private static func snapshot(
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
}
