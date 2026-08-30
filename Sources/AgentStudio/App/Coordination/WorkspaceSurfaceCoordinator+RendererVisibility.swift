import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Observation

@MainActor
extension WorkspaceSurfaceCoordinator {
    func bindRendererVisibility(toOwningWindowId windowId: UUID) {
        rendererVisibilityOwningWindowId = windowId
        surfaceManager.setAttachedBindingsChangeHandler { [weak self] in
            self?.restartRendererVisibilityObservation(trigger: .membershipChange)
        }
        restartRendererVisibilityObservation(trigger: .initialBind)
    }

    private func restartRendererVisibilityObservation(trigger: RendererVisibilityProjectionTrigger) {
        rendererVisibilityObservationGeneration &+= 1
        observeRendererVisibility(
            generation: rendererVisibilityObservationGeneration,
            trigger: trigger
        )
    }

    private func observeRendererVisibility(
        generation: UInt64,
        trigger: RendererVisibilityProjectionTrigger
    ) {
        withObservationTracking {
            let evaluationStart = ContinuousClock.now
            let result = surfaceManager.reconcileAttachedVisibility { paneID in
                self.effectiveRendererVisibility(forAttachedPaneID: paneID)
            }
            performanceTraceRecorder?.recordRendererVisibilityProjection(
                trigger: trigger,
                applied: result.applied,
                equal: result.equal,
                missing: result.missing,
                failed: result.failed,
                duration: evaluationStart.duration(to: .now)
            )
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self,
                    self.rendererVisibilityObservationGeneration == generation
                else { return }
                self.observeRendererVisibility(generation: generation, trigger: .observedChange)
            }
        }
    }

    func effectiveRendererVisibility(forAttachedPaneID paneID: UUID) -> Bool {
        let windowFacts =
            rendererVisibilityOwningWindowId
            .flatMap(windowLifecycleStore.presentationFacts(for:))
            ?? .hidden
        return windowFacts.isVisible
            && !windowFacts.isMiniaturized
            && !windowFacts.isOccluded
            && visibilityTierResolver.tier(for: PaneId(existingUUID: paneID)) == .p0Visible
    }
}
