import AgentStudioInfrastructure
import Foundation
import GhosttyKit

/// Renderer-state delivery and reconciliation for attached surfaces.
///
/// Split from `SurfaceManager.swift` so visibility/focus delivery stays separate from
/// lifecycle mutation. Reads `activeSurfaces`/`hiddenSurfaces` and defines
/// `deliverVisibility` directly; both are non-`private` in `SurfaceManager.swift` for
/// exactly this reason (Swift's `private` is file-scoped even across same-type extensions).
extension SurfaceManager {
    /// Outcome of one `deliverVisibility` call.
    ///
    /// Not `private`: it crosses from `SurfaceManager.swift`'s attach/detach/move/requeueUndo
    /// call sites into this file's `reconcileAttachedVisibility`, and Swift's `private`
    /// visibility is file-scoped even across extensions of the same type.
    enum VisibilityDeliveryResult {
        case applied
        case equal
        case missing
    }

    /// Delivers `visible` through `rendererStateDelivery`, suppressing the call when it equals
    /// the surface's last delivered value. On a successful transition to not-visible, also
    /// delivers focus=false through the same seam. Not `private` for the reason above.
    @discardableResult
    func deliverVisibility(_ surfaceId: UUID, visible: Bool) -> VisibilityDeliveryResult {
        guard var managed = activeSurfaces[surfaceId] ?? hiddenSurfaces[surfaceId] else {
            return .missing
        }

        guard managed.lastDeliveredVisibility != visible else {
            return .equal
        }

        guard rendererStateDelivery.deliverVisibility(visible, to: managed.surface) else {
            return .missing
        }

        if !visible {
            _ = rendererStateDelivery.deliverFocus(false, to: managed.surface)
        }

        managed.lastDeliveredVisibility = visible
        if activeSurfaces[surfaceId] != nil {
            activeSurfaces[surfaceId] = managed
        } else if hiddenSurfaces[surfaceId] != nil {
            hiddenSurfaces[surfaceId] = managed
        }
        return .applied
    }

    /// The last renderer visibility delivered for a surface, or `nil` if the surface has never
    /// received a delivery (or is not manager-owned).
    package func lastDeliveredVisibility(for surfaceID: UUID) -> Bool? {
        (activeSurfaces[surfaceID] ?? hiddenSurfaces[surfaceID])?.lastDeliveredVisibility
    }

    /// Reconciles renderer visibility for every attached surface against its pane's current
    /// desired visibility, delivering only where the desired value differs from the last
    /// delivered value. Hidden surfaces and undo-stack entries are never touched.
    package func reconcileAttachedVisibility(
        _ visibilityForPaneID: (UUID) -> Bool
    ) -> SurfaceVisibilityReconciliationResult {
        var applied = 0
        var equal = 0
        var missing = 0

        for (surfaceID, managed) in activeSurfaces {
            guard case .active(let paneID) = managed.state else { continue }
            let desiredVisibility = visibilityForPaneID(paneID)
            switch deliverVisibility(surfaceID, visible: desiredVisibility) {
            case .applied:
                applied += 1
            case .equal:
                equal += 1
            case .missing:
                missing += 1
            }
        }

        return SurfaceVisibilityReconciliationResult(applied: applied, equal: equal, missing: missing)
    }

    /// Set focus state for a surface
    func setFocus(_ surfaceId: UUID, focused: Bool) {
        guard let managed = activeSurfaces[surfaceId] ?? hiddenSurfaces[surfaceId],
            let surface = managed.surface.surface
        else {
            RestoreTrace.log(
                "SurfaceManager.setFocus skipped surface=\(surfaceId) focused=\(focused) known=\((activeSurfaces[surfaceId] != nil) || (hiddenSurfaces[surfaceId] != nil))"
            )
            return
        }
        ghostty_surface_set_focus(surface, focused)
        RestoreTrace.log("SurfaceManager.setFocus surface=\(surfaceId) focused=\(focused)")
    }

    /// Sync all surface focus states. Only activeSurfaceId gets focus=true; all others get false.
    /// Mirrors Ghostty's BaseTerminalController.syncFocusToSurfaceTree() pattern.
    package func syncFocus(activeSurfaceId: UUID?) {
        RestoreTrace.log(
            "SurfaceManager.syncFocus activeSurface=\(activeSurfaceId?.uuidString ?? "nil") activeCount=\(activeSurfaces.count)"
        )
        for (id, managed) in activeSurfaces {
            guard let surface = managed.surface.surface else { continue }
            ghostty_surface_set_focus(surface, id == activeSurfaceId)
            RestoreTrace.log("SurfaceManager.syncFocus set surface=\(id) focused=\(id == activeSurfaceId)")
        }
    }
}
