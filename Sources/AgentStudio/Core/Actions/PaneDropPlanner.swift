import AgentStudioInfrastructure
import Foundation

package enum PaneDropPreviewDecision: Equatable {
    case eligible(DropCommitPlan)
    case ineligible(PaneDropIneligibilityReason)
}

package enum PaneDropIneligibilityReason: Equatable {
    case managementLayerInactive
    case unsupportedPayload
    case drawerPanePayload
    case missingSourceTab(UUID)
    case drawerDestination
    case unsupportedSplitDirection(SplitNewDirection)
    case unresolvedDrop
    case validationFailed(ActionValidationError)
}

package enum DropCommitPlan: Equatable {
    case moveTab(tabId: UUID, insertionIndex: Int)
    case extractPaneToTabThenMove(paneId: UUID, sourceTabId: UUID, insertionIndex: Int)
    case paneAction(WorkspaceActionCommand)
}

package struct PaneSplitDropDestination: Equatable {
    let targetPaneId: UUID
    let targetTabId: UUID
    let direction: SplitNewDirection
    let sizingMode: DropSizingMode
    let targetDrawerParentPaneId: UUID?
}

package enum PaneDropDestination: Equatable {
    case splitTarget(PaneSplitDropDestination)
    case tabBarInsertion(insertionIndex: Int)
}

extension PaneDropDestination {
    package static func split(
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

package enum PaneDropPlanner {
    package static func previewDecision(
        payload: SplitDropPayload,
        destination: PaneDropDestination,
        state: ActionStateSnapshot
    ) -> PaneDropPreviewDecision {
        guard state.isManagementLayerActive else {
            return .ineligible(.managementLayerInactive)
        }

        switch destination {
        case .tabBarInsertion(let insertionIndex):
            return tabBarDecision(
                payload: payload,
                insertionIndex: insertionIndex,
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
        insertionIndex: Int,
        state: ActionStateSnapshot
    ) -> PaneDropPreviewDecision {
        guard case .existingPane(let paneId, let sourceTabId) = payload.kind else {
            return .ineligible(.unsupportedPayload)
        }
        guard state.drawerParentPaneId(of: paneId) == nil else {
            return .ineligible(.drawerPanePayload)
        }
        guard let sourceTab = state.tab(sourceTabId) else {
            return .ineligible(.missingSourceTab(sourceTabId))
        }

        if sourceTab.visiblePaneCount == 1 {
            let action = WorkspaceActionCommand.moveTab(tabId: sourceTabId, delta: 0)
            if let failure = actionValidationFailure(action, state: state) {
                return .ineligible(.validationFailed(failure))
            }
            return .eligible(.moveTab(tabId: sourceTabId, insertionIndex: insertionIndex))
        }

        let extractAction = WorkspaceActionCommand.extractPaneToTab(tabId: sourceTabId, paneId: paneId)
        if let failure = actionValidationFailure(extractAction, state: state) {
            return .ineligible(.validationFailed(failure))
        }

        return .eligible(
            .extractPaneToTabThenMove(
                paneId: paneId,
                sourceTabId: sourceTabId,
                insertionIndex: insertionIndex
            )
        )
    }

    private static func splitDecision(
        payload: SplitDropPayload,
        destination: PaneSplitDropDestination,
        state: ActionStateSnapshot
    ) -> PaneDropPreviewDecision {
        if destination.targetDrawerParentPaneId != nil {
            return .ineligible(.drawerDestination)
        }

        if case .existingPane(let sourcePaneId, _) = payload.kind,
            state.drawerParentPaneId(of: sourcePaneId) != nil
        {
            return .ineligible(.drawerPanePayload)
        }
        guard let zone = dropZoneSide(for: destination.direction) else {
            RestoreTrace.log(
                "PaneDropPlanner received unsupported split direction \(String(describing: destination.direction))")
            return .ineligible(.unsupportedSplitDirection(destination.direction))
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
            return .ineligible(.unresolvedDrop)
        }

        return eligiblePaneAction(action, state: state)
    }

    private static func eligiblePaneAction(
        _ action: WorkspaceActionCommand,
        state: ActionStateSnapshot
    ) -> PaneDropPreviewDecision {
        if let failure = actionValidationFailure(action, state: state) {
            return .ineligible(.validationFailed(failure))
        }
        return .eligible(.paneAction(action))
    }

    private static func actionValidationFailure(
        _ action: WorkspaceActionCommand,
        state: ActionStateSnapshot
    ) -> ActionValidationError? {
        let validation = WorkspaceCommandValidator.validate(action, state: state)
        if case .success = validation {
            return nil
        }
        RestoreTrace.log(
            "PaneDropPlanner rejected action \(String(describing: action)) validation=\(String(describing: validation))"
        )
        if case .failure(let failure) = validation {
            return failure
        }
        return nil
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
