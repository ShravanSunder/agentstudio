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

    @MainActor
    static func routeActionToTerminalRuntimeOnMainActor(
        actionTag: UInt32,
        payload: GhosttyAdapter.ActionPayload,
        surfaceViewObjectId: ObjectIdentifier,
        routingLookup: any GhosttyActionRoutingLookup
    ) -> Bool {
        guard let surfaceId = routingLookup.surfaceId(forViewObjectId: surfaceViewObjectId) else {
            traceGhosttyAction(
                body: "ghostty.action.dropped",
                actionTag: actionTag,
                payload: payload,
                signalClass: .unhandled,
                routeResult: false,
                reason: "surface_not_registered"
            )
            ghosttyLogger.warning("Dropped action tag \(actionTag): surface not registered in SurfaceManager")
            return false
        }
        guard let paneUUID = routingLookup.paneId(for: surfaceId) else {
            traceGhosttyAction(
                body: "ghostty.action.dropped",
                actionTag: actionTag,
                payload: payload,
                surfaceId: surfaceId,
                signalClass: .unhandled,
                routeResult: false,
                reason: "pane_not_mapped"
            )
            ghosttyLogger.warning("Dropped action tag \(actionTag): no pane mapped for surface \(surfaceId)")
            return false
        }
        let paneId = PaneId(existingUUID: paneUUID)
        let routedRuntime = runtimeRegistryForActionRouting.runtime(for: paneId) as? TerminalRuntime
        let runtime: TerminalRuntime?
        if let routedRuntime {
            runtime = routedRuntime
        } else if ObjectIdentifier(runtimeRegistryForActionRouting) != ObjectIdentifier(RuntimeRegistry.shared) {
            runtime = RuntimeRegistry.shared.runtime(for: paneId) as? TerminalRuntime
        } else {
            runtime = nil
        }

        guard let runtime else {
            traceGhosttyAction(
                body: "ghostty.action.dropped",
                actionTag: actionTag,
                payload: payload,
                paneId: paneUUID,
                surfaceId: surfaceId,
                signalClass: .unhandled,
                routeResult: false,
                reason: "runtime_not_found"
            )
            ghosttyLogger.warning(
                "Dropped action tag \(actionTag): terminal runtime not found for pane \(paneUUID)")
            return false
        }

        let event = GhosttyAdapter.shared.translate(actionTag: actionTag, payload: payload)
        traceGhosttyAction(
            body: "ghostty.action.translated",
            actionTag: actionTag,
            payload: payload,
            event: event,
            paneId: paneUUID,
            surfaceId: surfaceId,
            signalClass: signalClass(for: event, fallbackActionTag: actionTag),
            routeResult: true,
            reason: nil
        )
        traceTerminalStartupMilestones(
            actionTag: actionTag,
            event: event,
            paneID: paneUUID,
            surfaceID: surfaceId
        )
        GhosttyAdapter.shared.route(
            actionTag: actionTag,
            payload: payload,
            to: runtime
        )
        return true
    }
}
