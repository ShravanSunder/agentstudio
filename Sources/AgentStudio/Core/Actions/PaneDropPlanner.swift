import Foundation

enum PaneDropPreviewDecision: Equatable {
    case eligible(DropCommitPlan)
    case ineligible
}

enum DropCommitPlan: Equatable {
    case moveTab(tabId: UUID, toIndex: Int)
    case extractPaneToTabThenMove(paneId: UUID, sourceTabId: UUID, toIndex: Int)
    case paneAction(PaneActionCommand)
}

struct PaneSplitDropDestination: Equatable {
    let targetPaneId: UUID
    let targetTabId: UUID
    let direction: SplitNewDirection
    let sizingMode: DropSizingMode
    let targetDrawerParentPaneId: UUID?
}

enum PaneDropDestination: Equatable {
    case splitTarget(PaneSplitDropDestination)
    case tabBarInsertion(targetTabIndex: Int)
}

extension PaneDropDestination {
    static func split(
        targetPaneId: UUID,
        targetTabId: UUID,
        direction: SplitNewDirection,
        sizingMode: DropSizingMode,
        targetDrawerParentPaneId: UUID?
    ) -> Self {
        .splitTarget(
            PaneSplitDropDestination(
                targetPaneId: targetPaneId,
                targetTabId: targetTabId,
                direction: direction,
                sizingMode: sizingMode,
                targetDrawerParentPaneId: targetDrawerParentPaneId
            )
        )
    }
}

enum PaneDropPlanner {
    static func previewDecision(
        payload: SplitDropPayload,
        destination: PaneDropDestination,
        state: ActionStateSnapshot
    ) -> PaneDropPreviewDecision {
        guard state.isManagementLayerActive else {
            return .ineligible
        }

        switch destination {
        case .tabBarInsertion(let targetTabIndex):
            return tabBarDecision(
                payload: payload,
                targetTabIndex: targetTabIndex,
                state: state
            )
        case .splitTarget(let splitDestination):
            return splitDecision(
                payload: payload,
                destination: splitDestination,
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

        if sourceTab.visiblePaneCount == 1 {
            let action = PaneActionCommand.moveTab(tabId: sourceTabId, delta: 0)
            guard isActionValid(action, state: state) else {
                return .ineligible
            }
            return .eligible(.moveTab(tabId: sourceTabId, toIndex: targetTabIndex))
        }

        let extractAction = PaneActionCommand.extractPaneToTab(tabId: sourceTabId, paneId: paneId)
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
        destination: PaneSplitDropDestination,
        state: ActionStateSnapshot
    ) -> PaneDropPreviewDecision {
        if destination.targetDrawerParentPaneId != nil {
            return .ineligible
        }

        if case .existingPane(let sourcePaneId, _) = payload.kind,
            state.drawerParentPaneId(of: sourcePaneId) != nil
        {
            return .ineligible
        }
        guard let zone = dropZoneSide(for: destination.direction) else {
            RestoreTrace.log(
                "PaneDropPlanner received unsupported split direction \(String(describing: destination.direction))")
            return .ineligible
        }

        guard
            let action = WorkspaceCommandResolver.resolveDrop(
                payload: payload,
                destinationPaneId: destination.targetPaneId,
                destinationTabId: destination.targetTabId,
                zone: zone,
                sizingMode: destination.sizingMode,
                state: state
            )
        else {
            return .ineligible
        }

        return eligiblePaneAction(action, state: state)
    }

    private static func eligiblePaneAction(
        _ action: PaneActionCommand,
        state: ActionStateSnapshot
    ) -> PaneDropPreviewDecision {
        guard isActionValid(action, state: state) else {
            return .ineligible
        }
        return .eligible(.paneAction(action))
    }

    private static func isActionValid(
        _ action: PaneActionCommand,
        state: ActionStateSnapshot
    ) -> Bool {
        let validation = WorkspaceCommandValidator.validate(action, state: state)
        if case .success = validation {
            return true
        }
        RestoreTrace.log(
            "PaneDropPlanner rejected action \(String(describing: action)) validation=\(String(describing: validation))"
        )
        return false
    }

    private static func dropZoneSide(for direction: SplitNewDirection) -> DropZoneSide? {
        switch direction {
        case .left:
            return .left
        case .right:
            return .right
        case .up, .down:
            return nil
        }
    }
}
