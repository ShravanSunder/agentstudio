import Foundation

extension Ghostty.ActionRouter {
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
