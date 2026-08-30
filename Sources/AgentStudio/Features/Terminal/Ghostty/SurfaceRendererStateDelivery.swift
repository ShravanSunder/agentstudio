import Foundation
import GhosttyKit

@MainActor
package protocol SurfaceRendererStateDelivery: AnyObject {
    func deliverVisibility(_ visible: Bool, to surface: Ghostty.SurfaceView) -> Bool
    func deliverFocus(_ focused: Bool, to surface: Ghostty.SurfaceView) -> Bool
}

@MainActor
package protocol SurfaceFocusRequesting: AnyObject {
    func requestFocus(
        surfaceID: UUID,
        viewIdentity: ObjectIdentifier,
        focused: Bool
    ) -> Bool
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
