import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite("Ghostty clipboard callbacks")
struct GhosttyClipboardCallbackTests {
    @Test("readClipboard returns false when no surface userdata is available")
    func readClipboard_withoutUserdata_returnsFalse() {
        let handled = Ghostty.App.readClipboard(
            nil,
            location: GHOSTTY_CLIPBOARD_STANDARD,
            state: nil
        )

        #expect(!handled)
    }
}
