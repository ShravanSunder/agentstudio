import AppKit
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct HiddenSurfaceReadinessTests {
    @Test
    func restoredSurface_usesExplicitInitialGeometry_beforeProcessLaunch() {
        let config = Ghostty.SurfaceConfiguration(
            workingDirectory: "/tmp",
            startupStrategy: .surfaceCommand("/usr/local/bin/zmx attach session /bin/zsh -i -l"),
            initialFrame: NSRect(x: 0, y: 0, width: 1200, height: 700)
        )

        #expect(config.initialFrame == NSRect(x: 0, y: 0, width: 1200, height: 700))
    }

    @Test
    func zmxSurface_neverUsesDeferredShellAttach() {
        let strategy = Ghostty.SurfaceStartupStrategy.surfaceCommand(
            "/usr/local/bin/zmx attach session /bin/zsh -i -l"
        )

        #expect(strategy.startupCommandForSurface != nil)
    }

    @Test
    func restoredSurface_staysHidden_untilAttachOutcomeKnown() {
        #expect(
            HiddenSurfaceReadiness.revealState(
                processExited: false,
                startupWindowElapsed: false
            ) == .restoring
        )
    }

    @Test
    func hiddenAttachedSurface_clearsFocus_whenOccluded() {
        #expect(
            HiddenSurfaceReadiness.focusedStateAfterOcclusion(true) == false
        )
    }
}
