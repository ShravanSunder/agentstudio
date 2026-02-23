import AppKit
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite("Ghostty action routing")
struct GhosttyActionRoutingTests {
    @Test(
        "routing with resolved surface object identifier returns false when surface is unknown"
    )
    func routeWithResolvedSurfaceView_unknownSurface() {
        let unknownSurfaceViewId = ObjectIdentifier(NSView(frame: .zero))

        let routed = Ghostty.App.routeActionToTerminalRuntimeOnMainActor(
            actionTag: UInt32(GHOSTTY_ACTION_NEW_TAB.rawValue),
            payload: .noPayload,
            surfaceViewObjectId: unknownSurfaceViewId
        )

        #expect(!routed)
    }
}
