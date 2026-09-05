import AgentStudioCore
import Foundation
import Observation

/// Joins the surface manager's attached-surface bindings against the owning window's
/// presentation facts and the current visibility-tier projection, then asks the surface
/// manager to reconcile renderer visibility for the exact attached set. Mirrors
/// `WorkspaceSurfaceCoordinator+RepositoryFactDemand`'s generation-guarded
/// `withObservationTracking` restart shape: the attached-bindings handler and every
/// tracked read (window facts, active tab, minimized set, zoom, drawer expansion) rearm
/// the same observation loop.
@MainActor
extension WorkspaceSurfaceCoordinator {
    func bindRendererVisibility(toOwningWindowId windowId: UUID) {
        rendererVisibilityOwningWindowId = windowId
        surfaceManager.setAttachedBindingsChangeHandler { [weak self] in
            self?.restartRendererVisibilityObservation()
        }
        restartRendererVisibilityObservation()
    }

    func stopRendererVisibilityObservation() {
        rendererVisibilityObservationGeneration &+= 1
        surfaceManager.setAttachedBindingsChangeHandler(nil)
    }

    private func restartRendererVisibilityObservation() {
        rendererVisibilityObservationGeneration &+= 1
        observeRendererVisibility(generation: rendererVisibilityObservationGeneration)
    }

    private func observeRendererVisibility(generation: UInt64) {
        withObservationTracking {
            _ = surfaceManager.reconcileAttachedVisibility { paneID in
                self.effectiveRendererVisibility(forAttachedPaneID: paneID)
            }
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, self.rendererVisibilityObservationGeneration == generation else { return }
                self.observeRendererVisibility(generation: generation)
            }
        }
    }

    func effectiveRendererVisibility(forAttachedPaneID paneID: UUID) -> Bool {
        let windowFacts =
            rendererVisibilityOwningWindowId
            .flatMap(windowLifecycleStore.presentationFacts(for:)) ?? .hidden
        return windowFacts.isVisible && !windowFacts.isMiniaturized && !windowFacts.isOccluded
            && visibilityTierResolver.tier(for: PaneId(existingUUID: paneID)) == .p0Visible
    }
}
