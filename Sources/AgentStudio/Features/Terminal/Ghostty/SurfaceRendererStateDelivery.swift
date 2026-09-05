import Foundation
import GhosttyKit

/// The one boundary through which `SurfaceManager` reaches libghostty's renderer state calls.
///
/// Pinned Ghostty (v1.3.1) queues renderer work on every `ghostty_surface_set_occlusion` call
/// even when the value is unchanged, so the manager suppresses equal deliveries before it
/// reaches this seam. Tests substitute a recording implementation; production uses
/// `LiveSurfaceRendererStateDelivery.shared`.
@MainActor
package protocol SurfaceRendererStateDelivery: AnyObject {
    /// Returns `false` when the surface has no live native handle; no side effect occurred.
    @discardableResult
    func deliverVisibility(_ visible: Bool, to surface: Ghostty.SurfaceView) -> Bool

    /// Returns `false` when the surface has no live native handle; no side effect occurred.
    @discardableResult
    func deliverFocus(_ focused: Bool, to surface: Ghostty.SurfaceView) -> Bool
}

@MainActor
package final class LiveSurfaceRendererStateDelivery: SurfaceRendererStateDelivery {
    package static let shared = LiveSurfaceRendererStateDelivery()

    private init() {}

    package func deliverVisibility(_ visible: Bool, to surface: Ghostty.SurfaceView) -> Bool {
        guard let nativeSurface = surface.surface else { return false }
        ghostty_surface_set_occlusion(nativeSurface, visible)
        return true
    }

    package func deliverFocus(_ focused: Bool, to surface: Ghostty.SurfaceView) -> Bool {
        guard let nativeSurface = surface.surface else { return false }
        ghostty_surface_set_focus(nativeSurface, focused)
        return true
    }
}
