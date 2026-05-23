import Testing

@testable import AgentStudio

@Suite("GhosttyAppHandle")
@MainActor
struct GhosttyAppHandleTests {
    @Test("ghostty config override disables built-in scroll-to-bottom behavior")
    func configOverrideContainsExpectedScrollBehavior() {
        let overrideContents = Ghostty.AppHandle.scrollBehaviorOverrideContents

        #expect(overrideContents.contains("scroll-to-bottom = no-keystroke, no-output"))
    }

    @Test("ghostty config override removes cmd-k clear scrollback binding")
    func configOverrideRemovesCmdKClearScrollbackBinding() {
        let overrideContents = Ghostty.AppHandle.scrollBehaviorOverrideContents

        #expect(overrideContents.contains("keybind = cmd+k=unbind"))
    }
}
