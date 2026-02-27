import Foundation

enum PaneDropPreviewDecision: Equatable {
    case eligible(DropCommitPlan)
    case ineligible
}

enum DropCommitPlan: Equatable {
    case moveTab(tabId: UUID, toIndex: Int)
    case extractPaneToTabThenMove(paneId: UUID, sourceTabId: UUID, toIndex: Int)
    case paneAction(PaneAction)
}

enum PaneDropDestination: Equatable {
    case split(
        targetPaneId: UUID,
        targetTabId: UUID,
        direction: SplitNewDirection,
        targetDrawerParentPaneId: UUID?
    )
    case tabBarInsertion(targetTabIndex: Int)
}

enum PaneDropPlanner {
    static func previewDecision(
        payload: SplitDropPayload,
        destination: PaneDropDestination,
        state: ActionStateSnapshot
    ) -> PaneDropPreviewDecision {
        guard state.isManagementModeActive else {
            return .ineligible
        }

        switch destination {
        case .tabBarInsertion(let targetTabIndex):
            return tabBarDecision(
                payload: payload,
                targetTabIndex: targetTabIndex,
                state: state
            )
        case .split(let targetPaneId, let targetTabId, let direction, let targetDrawerParentPaneId):
            return splitDecision(
                payload: payload,
                targetPaneId: targetPaneId,
                targetTabId: targetTabId,
                direction: direction,
                targetDrawerParentPaneId: targetDrawerParentPaneId,
                state: state
            )
        }
    }

    private static func tabBarDecision(
        payload: SplitDropPayload,
        targetTabIndex: Int,
        state: ActionStateSnapshot
    ) -> PaneDropPreviewDecision {
        guard case .existingPane(let paneId, let sourceTabId) = payload.kind else {
            return .ineligible
        }
        guard state.drawerParentPaneId(of: paneId) == nil else {
            return .ineligible
        }
        guard let sourceTab = state.tab(sourceTabId) else {
            return .ineligible
        }

        if sourceTab.paneCount == 1 {
            let action = PaneAction.moveTab(tabId: sourceTabId, delta: 0)
            guard isActionValid(action, state: state) else {
                return .ineligible
            }
            return .eligible(.moveTab(tabId: sourceTabId, toIndex: targetTabIndex))
        }

        let extractAction = PaneAction.extractPaneToTab(tabId: sourceTabId, paneId: paneId)
        guard isActionValid(extractAction, state: state) else {
            return .ineligible
        }

        return .eligible(
            .extractPaneToTabThenMove(
                paneId: paneId,
                sourceTabId: sourceTabId,
                toIndex: targetTabIndex
            )
        )
    }

    private static func splitDecision(
        payload: SplitDropPayload,
        targetPaneId: UUID,
        targetTabId: UUID,
        direction: SplitNewDirection,
        targetDrawerParentPaneId: UUID?,
        state: ActionStateSnapshot
    ) -> PaneDropPreviewDecision {
        if let drawerParentPaneId = targetDrawerParentPaneId {
            guard case .existingPane(let sourcePaneId, _) = payload.kind else {
                return .ineligible
            }
            guard sourcePaneId != targetPaneId else {
                return .ineligible
            }
            guard state.drawerParentPaneId(of: sourcePaneId) == drawerParentPaneId else {
                return .ineligible
            }
            let action = PaneAction.moveDrawerPane(
                parentPaneId: drawerParentPaneId,
                drawerPaneId: sourcePaneId,
                targetDrawerPaneId: targetPaneId,
                direction: direction
            )
            return eligiblePaneAction(action, state: state)
        }

        if case .existingPane(let sourcePaneId, _) = payload.kind,
            state.drawerParentPaneId(of: sourcePaneId) != nil
        {
            return .ineligible
        }

        guard
            let action = ActionResolver.resolveDrop(
                payload: payload,
                destinationPaneId: targetPaneId,
                destinationTabId: targetTabId,
                zone: dropZone(for: direction),
                state: state
            )
        else {
            return .ineligible
        }

        return eligiblePaneAction(action, state: state)
    }

    private static func eligiblePaneAction(
        _ action: PaneAction,
        state: ActionStateSnapshot
    ) -> PaneDropPreviewDecision {
        guard isActionValid(action, state: state) else {
            return .ineligible
        }
        return .eligible(.paneAction(action))
    }

    private static func isActionValid(
        _ action: PaneAction,
        state: ActionStateSnapshot
    ) -> Bool {
        if case .success = ActionValidator.validate(action, state: state) {
            return true
        }
        return false
    }

    private static func dropZone(for direction: SplitNewDirection) -> DropZone {
        switch direction {
        case .left:
            return .left
        case .right:
            return .right
        case .up, .down:
            // Split drop zones are horizontal-only.
            return .right
        }
    }
}
