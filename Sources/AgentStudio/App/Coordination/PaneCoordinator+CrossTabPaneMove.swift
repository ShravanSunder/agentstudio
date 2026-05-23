import Foundation

@MainActor
extension PaneCoordinator {
    func executeMovePaneAcrossTabs(_ request: CrossTabPaneMoveRequest) {
        let paneId = request.paneId
        let sourceTabId = request.sourceTabId
        let destTabId = request.destTabId
        guard let pane = store.paneAtom.pane(paneId) else {
            Self.logger.warning("movePaneAcrossTabs: pane \(paneId) not found")
            return
        }

        let previousVisiblePaneIds = Set(arrangementView.activeVisiblePaneIds(forTab: sourceTabId))
        let drawer = pane.drawer
        let sourceTabDrainSnapshot = store.mutationCoordinator.snapshotForClose(tabId: sourceTabId)
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
        if result.sourceTabClosed, let sourceTabDrainSnapshot {
            appendUndoEntry(
                .crossTabSourceDrain(
                    WorkspaceMutationCoordinator.CrossTabSourceDrainSnapshot(
                        sourceTabSnapshot: sourceTabDrainSnapshot,
                        destinationTabId: destTabId,
                        movedPaneId: paneId,
                        drawerId: drawer?.drawerId,
                        drawerPaneIds: drawer?.paneIds ?? []
                    )
                )
            )
            expireOldUndoEntries()
        }
        let newVisiblePaneIds = Set(arrangementView.activeVisiblePaneIds(forTab: destTabId))
        let movedPaneIds = Set([paneId] + (drawer?.paneIds ?? []))
        for movedPaneId in movedPaneIds {
            detachForViewSwitch(paneId: movedPaneId)
        }
        reconcileVisiblePaneTransition(
            previousVisiblePaneIds: previousVisiblePaneIds.subtracting(movedPaneIds),
            newVisiblePaneIds: newVisiblePaneIds
        )
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
