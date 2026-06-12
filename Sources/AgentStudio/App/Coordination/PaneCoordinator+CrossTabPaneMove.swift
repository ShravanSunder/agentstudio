import Foundation

@MainActor
extension PaneCoordinator {
    struct CrossTabMoveViewTransitions: Equatable {
        let paneIdsToDetach: Set<UUID>
        let paneIdsToReattach: Set<UUID>
    }

    nonisolated static func computeCrossTabMoveViewTransitions(
        sourceVisibleBefore: Set<UUID>,
        destinationVisibleBefore: Set<UUID>,
        destinationVisibleAfter: Set<UUID>,
        movedPaneIds: Set<UUID>
    ) -> CrossTabMoveViewTransitions {
        let newlyVisibleDestinationPaneIds = destinationVisibleAfter.subtracting(destinationVisibleBefore)
        let movedPaneIdsVisibleAfterMove = destinationVisibleAfter.intersection(movedPaneIds)
        let hiddenDestinationPaneIds = destinationVisibleBefore.subtracting(destinationVisibleAfter)

        return CrossTabMoveViewTransitions(
            paneIdsToDetach: sourceVisibleBefore.union(movedPaneIds).union(hiddenDestinationPaneIds),
            paneIdsToReattach: newlyVisibleDestinationPaneIds.union(movedPaneIdsVisibleAfterMove)
        )
    }

    func executeMovePaneAcrossTabs(_ request: CrossTabPaneMoveRequest) {
        let paneId = request.paneId
        let sourceTabId = request.sourceTabId
        let destTabId = request.destTabId
        guard let pane = store.paneAtom.pane(paneId) else {
            Self.logger.warning("movePaneAcrossTabs: pane \(paneId) not found")
            return
        }

        let sourceVisibleBefore = Set(arrangementView.activeVisiblePaneIds(forTab: sourceTabId))
        let destinationVisibleBefore = Set(arrangementView.activeVisiblePaneIds(forTab: destTabId))
        let drawer = pane.drawer
        let movedPaneIds = Set([paneId] + (drawer?.paneIds ?? []))
        guard
            let result = store.tabLayoutAtom.movePaneAcrossTabs(
                CrossTabPaneMoveMutation(
                    request: request,
                    drawerId: drawer?.drawerId,
                    drawerPaneIds: drawer?.paneIds ?? []
                )
            )
        else {
            Self.logger.warning("movePaneAcrossTabs: failed moving pane \(paneId) into tab \(destTabId)")
            return
        }

        RestoreTrace.log(
            PaneArrangementTraceMessages.crossTabPaneMove(
                paneId: paneId,
                sourceTabId: sourceTabId,
                destTabId: destTabId,
                sourceTabClosed: result.sourceTabClosed
            )
        )
        let destinationVisibleAfter = Set(arrangementView.activeVisiblePaneIds(forTab: destTabId))
        let transitions = Self.computeCrossTabMoveViewTransitions(
            sourceVisibleBefore: sourceVisibleBefore,
            destinationVisibleBefore: destinationVisibleBefore,
            destinationVisibleAfter: destinationVisibleAfter,
            movedPaneIds: movedPaneIds
        )
        for paneIdToDetach in transitions.paneIdsToDetach {
            detachForViewSwitch(paneId: paneIdToDetach)
        }
        for paneIdToReattach in transitions.paneIdsToReattach {
            reattachForViewSwitch(paneId: paneIdToReattach)
        }
        restoreViewsForActiveTabIfNeeded(forceWhenBoundsExist: true)
        focusVisiblePaneHost(paneId)
    }

    func reconcileVisiblePaneTransition(previousVisiblePaneIds: Set<UUID>, newVisiblePaneIds: Set<UUID>) {
        for paneId in previousVisiblePaneIds.subtracting(newVisiblePaneIds) {
            detachForViewSwitch(paneId: paneId)
        }
        for paneId in newVisiblePaneIds.subtracting(previousVisiblePaneIds) {
            restoreVisiblePaneIfNeeded(paneId, forceWhenBoundsExist: true)
            if viewRegistry.terminalView(for: paneId) != nil {
                reattachForViewSwitch(paneId: paneId)
            }
        }
    }
}
