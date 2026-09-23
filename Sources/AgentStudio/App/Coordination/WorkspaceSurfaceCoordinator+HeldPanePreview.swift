import AgentStudioCore
import AgentStudioTerminal
import AppKit

@MainActor
struct HeldPanePreviewPreparationCapture: Equatable {
    let generation: UInt64
    let target: ValidatedPanePreviewTarget
    let terminalContainerBounds: NSRect
}

@MainActor
extension WorkspaceSurfaceCoordinator {
    func bindHeldPanePreviewState(_ state: HeldPanePreviewState) {
        heldPanePreviewState = state
        restartBridgePaneActivityObservation()
        restartRendererVisibilityObservation()
    }

    func prepareHeldPanePreview() -> Task<Void, Never>? {
        guard let state = heldPanePreviewState,
            state.isHeld,
            let generation = state.generation,
            let target = state.requestedTarget
        else {
            heldPanePreviewPreparationCapture = nil
            return nil
        }

        guard let pane = currentPane(for: target) else {
            heldPanePreviewPreparationCapture = nil
            _ = state.invalidateTarget(generation: generation, target: target)
            return nil
        }

        let terminalContainerBounds = windowLifecycleStore.terminalContainerBounds
        guard !terminalContainerBounds.isEmpty
        else {
            heldPanePreviewPreparationCapture = nil
            _ = state.markPresentationUnavailable(generation: generation, target: target)
            return nil
        }

        let capture = HeldPanePreviewPreparationCapture(
            generation: generation,
            target: target,
            terminalContainerBounds: terminalContainerBounds
        )
        heldPanePreviewPreparationCapture = capture
        _ = preparedContentVisibilitySignalHandler(
            currentVisibleQueuedSet(includingAtLeast: PaneId(existingUUID: target.paneID))
        )

        if let terminalView = viewRegistry.terminalView(for: pane.id),
            let surfaceID = terminalView.surfaceId
        {
            guard let surfaceView = surfaceManager.attach(surfaceID, to: pane.id) else {
                heldPanePreviewPreparationCapture = nil
                _ = state.markPresentationUnavailable(generation: generation, target: target)
                return nil
            }
            terminalView.displaySurface(surfaceView, geometryVerificationReason: "heldPanePreview")
            terminalView.forceGeometrySync(reason: "heldPanePreview")
            acceptHeldPanePreviewIfCurrent(capture)
            return nil
        }

        if previewMountIsReady(for: pane) {
            acceptHeldPanePreviewIfCurrent(capture)
            return nil
        }

        _ = createViewForContent(
            pane: pane,
            initialFrame: terminalContainerBounds,
            treatAsRestoredSessionStart: true
        )

        if previewMountIsReady(for: pane) {
            acceptHeldPanePreviewIfCurrent(capture)
            return nil
        } else {
            return scheduleHeldPreviewDeferredTerminalGeometryReevaluation(capture)
        }
    }

    private func scheduleHeldPreviewDeferredTerminalGeometryReevaluation(
        _ capture: HeldPanePreviewPreparationCapture
    ) -> Task<Void, Never>? {
        guard let preparedGeneration = acceptedPreparedContentMountGeneration,
            viewRegistry.preparedContentMountState(
                for: PaneId(existingUUID: capture.target.paneID),
                generation: preparedGeneration
            ) == .deferredGeometry(owner: .terminal)
        else {
            return nil
        }

        let scheduledPreparedGeneration = preparedGeneration
        return Task { @MainActor [weak self] in
            guard let self,
                self.isCurrentHeldPreviewCapture(capture),
                self.acceptedPreparedContentMountGeneration == scheduledPreparedGeneration,
                self.viewRegistry.preparedContentMountState(
                    for: PaneId(existingUUID: capture.target.paneID),
                    generation: scheduledPreparedGeneration
                ) == .deferredGeometry(owner: .terminal)
            else {
                return
            }

            _ = self.preparedContentVisibilitySignalHandler(
                self.currentVisibleQueuedSetPreservingHeldPreview()
            )
            guard self.isCurrentHeldPreviewCapture(capture) else { return }
            await self.preparedTerminalGeometryReevaluationHandler([
                PaneId(existingUUID: capture.target.paneID): capture.terminalContainerBounds
            ])
        }
    }

    private func isCurrentHeldPreviewCapture(
        _ capture: HeldPanePreviewPreparationCapture
    ) -> Bool {
        guard heldPanePreviewPreparationCapture == capture,
            let state = heldPanePreviewState,
            state.isHeld,
            state.generation == capture.generation,
            state.requestedTarget == capture.target,
            currentPane(for: capture.target) != nil,
            windowLifecycleStore.terminalContainerBounds == capture.terminalContainerBounds
        else {
            return false
        }
        return true
    }

    func currentVisibleQueuedSetPreservingHeldPreview() -> PreparedContentVisibleQueuedSet {
        guard let state = heldPanePreviewState,
            state.isHeld,
            let target = state.requestedTarget
        else {
            return currentVisibleQueuedSet()
        }
        return currentVisibleQueuedSet(includingAtLeast: PaneId(existingUUID: target.paneID))
    }

    func currentHeldPreviewTarget() -> (target: ValidatedPanePreviewTarget, pane: Pane)? {
        guard let state = heldPanePreviewState,
            state.isHeld,
            let target = state.presentedTarget,
            let pane = currentPane(for: target)
        else {
            return nil
        }
        return (target, pane)
    }

    func acceptHeldPanePreviewIfCurrent(
        _ capture: HeldPanePreviewPreparationCapture,
        paneID: UUID? = nil
    ) {
        guard heldPanePreviewPreparationCapture == capture,
            let state = heldPanePreviewState,
            state.isHeld,
            state.generation == capture.generation,
            state.requestedTarget == capture.target,
            let currentPane = currentPane(for: capture.target),
            windowLifecycleStore.terminalContainerBounds == capture.terminalContainerBounds,
            paneID.map({ $0 == capture.target.paneID }) ?? true
        else {
            return
        }

        if let terminalView = viewRegistry.terminalView(for: capture.target.paneID) {
            guard let surfaceID = terminalView.surfaceId,
                let surfaceView = surfaceManager.attach(surfaceID, to: capture.target.paneID)
            else {
                return
            }
            if terminalView.ghosttySurface !== surfaceView {
                terminalView.displaySurface(surfaceView, geometryVerificationReason: "heldPanePreview")
            }
        }

        guard previewMountIsReady(for: currentPane) else { return }

        heldPanePreviewPreparationCapture = nil
        _ = state.acceptPresentedTarget(capture.target, generation: capture.generation)
    }

    private func currentPane(for target: ValidatedPanePreviewTarget) -> Pane? {
        guard let pane = store.paneAtom.pane(target.paneID),
            store.tabLayoutAtom.tabID(containingPane: pane.parentPaneId ?? pane.id)
                == target.owningTabID,
            pane.provider == target.provider,
            pane.terminalState?.zmxSessionID == target.sessionID
        else {
            return nil
        }
        return pane
    }

    private func previewMountIsReady(for pane: Pane) -> Bool {
        guard let host = viewRegistry.view(for: pane.id),
            let mountedContentView = host.mountedContentView
        else {
            return false
        }

        if let terminalView = mountedContentView as? TerminalPaneMountView {
            return terminalView.surfaceId != nil && terminalView.ghosttySurface != nil
        }
        if case .bridgePanel = pane.content {
            return viewRegistry.allBridgeViews[pane.id] != nil
                && bridgePaneRetirementTasksByPaneId[pane.id] == nil
        }
        return true
    }

}
