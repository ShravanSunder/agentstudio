import Foundation

@MainActor
extension PaneTabViewController {
    nonisolated static func resolveDrawerMoveDropAction(
        payload: SplitDropPayload,
        destinationPane: Pane?,
        sourcePane: Pane?,
        zone: DropZone,
        layout: DrawerGridLayout?
    ) -> PaneActionCommand? {
        guard case .existingPane(let sourcePaneId, _) = payload.kind else { return nil }
        guard let destinationPane, let destinationParentPaneId = destinationPane.parentPaneId else { return nil }
        guard destinationPane.id != sourcePaneId else { return nil }
        guard sourcePane?.parentPaneId == destinationParentPaneId else { return nil }
        guard let layout else { return nil }
        guard
            let target = layout.legacyMoveTarget(
                targetPaneId: destinationPane.id,
                direction: splitDirection(for: zone)
            )
        else { return nil }

        return .moveDrawerPane(
            parentPaneId: destinationParentPaneId,
            drawerPaneId: sourcePaneId,
            target: target
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
