import Testing

@testable import AgentStudioTerminal

@Suite
struct GhosttySurfaceViewFocusAuthorityTests {
    @Test("stale focused left surface rejects key equivalent owned by right first responder")
    func staleFocusedLeftSurfaceRejectsRightResponderKeyEquivalent() {
        let leftSurfaceAccepts = Ghostty.SurfaceView.shouldAcceptKeyEquivalent(
            isFocused: true,
            isWindowFirstResponder: false
        )
        let rightSurfaceAccepts = Ghostty.SurfaceView.shouldAcceptKeyEquivalent(
            isFocused: true,
            isWindowFirstResponder: true
        )

        #expect(!leftSurfaceAccepts)
        #expect(rightSurfaceAccepts)
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
