import Foundation
import GhosttyKit

extension Ghostty.ActionRouter {
    static func surfaceView(from surface: ghostty_surface_t) -> Ghostty.SurfaceView? {
        guard let userdata = ghostty_surface_userdata(surface) else { return nil }
        return Unmanaged<Ghostty.SurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    }

    @MainActor
    static func routeActionToTerminalRuntimeOnMainActor(
        actionTag: UInt32,
        payload: GhosttyAdapter.ActionPayload,
        surfaceViewObjectId: ObjectIdentifier
    ) -> Bool {
        routeActionToTerminalRuntimeOnMainActor(
            actionTag: actionTag,
            payload: payload,
            surfaceViewObjectId: surfaceViewObjectId,
            routingLookup: SurfaceManager.shared
        )
    }
}
