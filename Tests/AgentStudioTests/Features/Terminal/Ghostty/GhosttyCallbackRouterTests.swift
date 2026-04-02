import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite("Ghostty callback router")
struct GhosttyCallbackRouterTests {
    @Test("readClipboard returns false when no surface userdata is available")
    func readClipboard_withoutUserdata_returnsFalse() {
        let handled = Ghostty.CallbackRouter.readClipboardForTesting(
            nil,
            location: GHOSTTY_CLIPBOARD_STANDARD,
            state: nil
        )

        #expect(!handled)
    }
}
