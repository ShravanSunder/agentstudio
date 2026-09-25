import Testing

@testable import AgentStudioTerminal

@Suite
struct GhosttySurfaceViewFocusAuthorityTests {
    @Test("stale focused left surface rejects key equivalent owned by right first responder")
    func staleFocusedLeftSurfaceRejectsRightResponderKeyEquivalent() {
        let leftSurfaceAccepts = Ghostty.SurfaceView.shouldAcceptKeyEquivalent(
            cachedFocusState: true,
            isWindowFirstResponder: false
        )
        let rightSurfaceAccepts = Ghostty.SurfaceView.shouldAcceptKeyEquivalent(
            cachedFocusState: true,
            isWindowFirstResponder: true
        )

        #expect(!leftSurfaceAccepts)
        #expect(rightSurfaceAccepts)
    }

    @Test("actual first responder accepts key equivalents despite stale unfocused state")
    func actualFirstResponderOverridesStaleUnfocusedState() {
        let surfaceAccepts = Ghostty.SurfaceView.shouldAcceptKeyEquivalent(
            cachedFocusState: false,
            isWindowFirstResponder: true
        )

        #expect(surfaceAccepts)
    }

    @Test("detached surface cannot retain focused state")
    func detachedSurfaceCannotRetainFocusedState() {
        #expect(
            !Ghostty.SurfaceView.focusedStateAfterMovingToWindow(
                isFocused: true,
                isAttachedToWindow: false
            )
        )
        #expect(
            Ghostty.SurfaceView.focusedStateAfterMovingToWindow(
                isFocused: true,
                isAttachedToWindow: true
            )
        )
    }
}
