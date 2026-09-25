import Testing

@testable import AgentStudioTerminal

@Suite
struct GhosttySurfaceViewFocusAuthorityTests {
    @Test("key equivalent eligibility follows the live window first responder")
    func keyEquivalentEligibilityFollowsLiveWindowFirstResponder() {
        let leftSurfaceAccepts = Ghostty.SurfaceView.shouldAcceptKeyEquivalent(
            isWindowFirstResponder: false
        )
        let rightSurfaceAccepts = Ghostty.SurfaceView.shouldAcceptKeyEquivalent(
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
