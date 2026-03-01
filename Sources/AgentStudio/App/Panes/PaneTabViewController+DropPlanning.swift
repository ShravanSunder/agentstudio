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

    nonisolated static func splitDirection(for zone: DropZone) -> SplitNewDirection {
        switch zone {
        case .left:
            return .left
        case .right:
            return .right
        }
    }
}
