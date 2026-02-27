import Foundation

@MainActor
extension PaneTabViewController {
    func drawerMoveDropAction(
        payload: SplitDropPayload,
        destPaneId: UUID,
        zone: DropZone
    ) -> PaneAction? {
        let destinationPane = store.pane(destPaneId)
        let sourcePane: Pane? =
            if case .existingPane(let sourcePaneId, _) = payload.kind {
                store.pane(sourcePaneId)
            } else {
                nil
            }

        return Self.resolveDrawerMoveDropAction(
            payload: payload,
            destinationPane: destinationPane,
            sourcePane: sourcePane,
            zone: zone
        )
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
