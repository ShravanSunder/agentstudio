import AppKit
import Testing

@testable import AgentStudio

@Suite("GhosttySurfaceView initial frame invariant")
struct GhosttySurfaceViewInitialFrameTests {
    @Test("terminal surface creation rejects nil initial frame")
    func terminalSurfaceCreation_rejectsMissingInitialFrame() {
        let config = Ghostty.SurfaceConfiguration(
            launchDirectory: nil,
            startupStrategy: .surfaceCommand(nil),
            initialFrame: nil
        )

        #expect(config.hasValidInitialFrameForSurfaceCreation == false)
    }

    @Test("terminal surface creation rejects empty initial frame")
    func terminalSurfaceCreation_rejectsEmptyInitialFrame() {
        let config = Ghostty.SurfaceConfiguration(
            launchDirectory: nil,
            startupStrategy: .surfaceCommand(nil),
            initialFrame: .zero
        )

        #expect(config.hasValidInitialFrameForSurfaceCreation == false)
    }

    @Test("terminal surface creation accepts non-empty initial frame")
    func terminalSurfaceCreation_acceptsNonEmptyInitialFrame() {
        let config = Ghostty.SurfaceConfiguration(
            launchDirectory: nil,
            startupStrategy: .surfaceCommand(nil),
            initialFrame: NSRect(x: 0, y: 0, width: 640, height: 480)
        )

        #expect(config.hasValidInitialFrameForSurfaceCreation == true)
    }
}
