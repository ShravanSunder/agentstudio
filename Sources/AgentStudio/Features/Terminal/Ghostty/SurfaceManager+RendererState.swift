import AgentStudioInfrastructure
import Foundation

extension SurfaceManager {
    package func lastDeliveredVisibility(for surfaceID: UUID) -> Bool? {
        (activeSurfaces[surfaceID] ?? hiddenSurfaces[surfaceID])?.lastDeliveredVisibility
    }

    package func reconcileAttachedVisibility(
        _ visibilityForPaneID: (UUID) -> Bool
    ) -> SurfaceVisibilityReconciliationResult {
        var desiredVisibilityBySurfaceID: [UUID: Bool] = [:]
        for (surfaceID, managedSurface) in activeSurfaces {
            guard case .active(let paneID) = managedSurface.state else { continue }
            desiredVisibilityBySurfaceID[surfaceID] = visibilityForPaneID(paneID)
        }
        return reconcileAttachedVisibility(desiredVisibilityBySurfaceID)
    }

    package func setAttachedBindingsChangeHandler(_ handler: (() -> Void)?) {
        onAttachedBindingsChanged = handler.map { handler in
            { _ in handler() }
        }
    }

    package func reconcileAttachedVisibility(
        _ desiredVisibilityBySurfaceID: [UUID: Bool]
    ) -> SurfaceVisibilityReconciliationResult {
        var applied = 0
        var equal = 0
        var failed = 0

        for surfaceID in activeSurfaces.keys {
            switch deliverVisibility(
                surfaceID,
                visible: desiredVisibilityBySurfaceID[surfaceID] ?? false
            ) {
            case .applied:
                applied += 1
            case .equal:
                equal += 1
            case .missing, .failed:
                failed += 1
            }
        }

        let missing = desiredVisibilityBySurfaceID.keys.count(where: { activeSurfaces[$0] == nil })
        return SurfaceVisibilityReconciliationResult(
            applied: applied,
            equal: equal,
            missing: missing,
            failed: failed
        )
    }

    @discardableResult
    package func requestFocus(
        surfaceID: UUID,
        viewIdentity: ObjectIdentifier,
        focused: Bool
    ) -> Bool {
        guard surfaceViewToId[viewIdentity] == surfaceID,
            let managed = activeSurfaces[surfaceID] ?? hiddenSurfaces[surfaceID],
            ObjectIdentifier(managed.surface) == viewIdentity
        else {
            return false
        }
        if focused {
            guard activeSurfaces[surfaceID] != nil, managed.lastDeliveredVisibility == true else {
                return false
            }
        }
        return rendererStateDelivery.deliverFocus(focused, to: managed.surface)
    }

    func setFocus(_ surfaceID: UUID, focused: Bool) {
        guard let managed = activeSurfaces[surfaceID] ?? hiddenSurfaces[surfaceID] else {
            RestoreTrace.log(
                "SurfaceManager.setFocus skipped surface=\(surfaceID) focused=\(focused) known=\((activeSurfaces[surfaceID] != nil) || (hiddenSurfaces[surfaceID] != nil))"
            )
            return
        }
        _ = requestFocus(
            surfaceID: surfaceID,
            viewIdentity: ObjectIdentifier(managed.surface),
            focused: focused
        )
        RestoreTrace.log("SurfaceManager.setFocus surface=\(surfaceID) focused=\(focused)")
    }

    /// Sync all surface focus states. Only activeSurfaceId gets focus=true; all others get false.
    /// Mirrors Ghostty's BaseTerminalController.syncFocusToSurfaceTree() pattern.
    package func syncFocus(activeSurfaceId: UUID?) {
        RestoreTrace.log(
            "SurfaceManager.syncFocus activeSurface=\(activeSurfaceId?.uuidString ?? "nil") activeCount=\(activeSurfaces.count)"
        )
        for (surfaceID, managed) in activeSurfaces {
            _ = requestFocus(
                surfaceID: surfaceID,
                viewIdentity: ObjectIdentifier(managed.surface),
                focused: surfaceID == activeSurfaceId
            )
            RestoreTrace.log(
                "SurfaceManager.syncFocus set surface=\(surfaceID) focused=\(surfaceID == activeSurfaceId)"
            )
        }
    }

    enum VisibilityDeliveryResult {
        case applied
        case equal
        case missing
        case failed
    }

    func deliverVisibility(
        _ surfaceID: UUID,
        visible: Bool
    ) -> VisibilityDeliveryResult {
        if var managed = activeSurfaces[surfaceID] {
            guard managed.lastDeliveredVisibility != visible else {
                performanceTraceRecorder?.recordRendererVisibilityDelivery(
                    surfaceID: surfaceID,
                    visible: visible,
                    outcome: .equal
                )
                return .equal
            }
            guard rendererStateDelivery.deliverVisibility(visible, to: managed.surface) else {
                performanceTraceRecorder?.recordRendererVisibilityDelivery(
                    surfaceID: surfaceID,
                    visible: visible,
                    outcome: .failed
                )
                return .failed
            }
            if !visible {
                _ = rendererStateDelivery.deliverFocus(false, to: managed.surface)
            }
            managed.lastDeliveredVisibility = visible
            activeSurfaces[surfaceID] = managed
            performanceTraceRecorder?.recordRendererVisibilityDelivery(
                surfaceID: surfaceID,
                visible: visible,
                outcome: .applied
            )
            return .applied
        }
        if var managed = hiddenSurfaces[surfaceID] {
            guard managed.lastDeliveredVisibility != visible else {
                performanceTraceRecorder?.recordRendererVisibilityDelivery(
                    surfaceID: surfaceID,
                    visible: visible,
                    outcome: .equal
                )
                return .equal
            }
            guard rendererStateDelivery.deliverVisibility(visible, to: managed.surface) else {
                performanceTraceRecorder?.recordRendererVisibilityDelivery(
                    surfaceID: surfaceID,
                    visible: visible,
                    outcome: .failed
                )
                return .failed
            }
            if !visible {
                _ = rendererStateDelivery.deliverFocus(false, to: managed.surface)
            }
            managed.lastDeliveredVisibility = visible
            hiddenSurfaces[surfaceID] = managed
            performanceTraceRecorder?.recordRendererVisibilityDelivery(
                surfaceID: surfaceID,
                visible: visible,
                outcome: .applied
            )
            return .applied
        }
        performanceTraceRecorder?.recordRendererVisibilityDelivery(
            surfaceID: surfaceID,
            visible: visible,
            outcome: .missing
        )
        return .missing
    }
}
