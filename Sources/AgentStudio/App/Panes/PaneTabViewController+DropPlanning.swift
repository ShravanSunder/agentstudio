import Foundation

@MainActor
extension PaneTabViewController {
    nonisolated static func tabBarDropCommitPlan(
        payload: PaneDragPayload,
        targetTabIndex: Int,
        state: ActionStateSnapshot
    ) -> DropCommitPlan? {
        guard targetTabIndex >= 0, targetTabIndex <= state.tabCount else { return nil }

        let splitPayload = SplitDropPayload(
            kind: .existingPane(paneId: payload.paneId, sourceTabId: payload.tabId)
        )
        let destination = PaneDropDestination.tabBarInsertion(targetTabIndex: targetTabIndex)
        let decision = PaneDropPlanner.previewDecision(
            payload: splitPayload,
            destination: destination,
            state: state
        )

        if case .eligible(let plan) = decision {
            return plan
        }
        return nil
    }

    nonisolated static func resolveDrawerMoveDropAction(
        payload: SplitDropPayload,
        destinationPane: Pane?,
        sourcePane: Pane?,
        zone: DropZone
    ) -> PaneAction? {
        guard case .existingPane(let sourcePaneId, _) = payload.kind else { return nil }
        guard let destinationPane, let destinationParentPaneId = destinationPane.parentPaneId else { return nil }
        guard destinationPane.id != sourcePaneId else { return nil }
        guard sourcePane?.parentPaneId == destinationParentPaneId else { return nil }

        return .moveDrawerPane(
            parentPaneId: destinationParentPaneId,
            drawerPaneId: sourcePaneId,
            targetDrawerPaneId: destinationPane.id,
            direction: splitDirection(for: zone)
        )
    }

    nonisolated static func splitDirection(for zone: DropZone) -> SplitNewDirection {
        switch zone {
        case .left:
            return .left
        case .right:
            return .right
        }
    }
}
