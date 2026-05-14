import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite("Ghostty callback router")
struct GhosttyCallbackRouterTests {
    @Test("readClipboard returns false when no surface userdata is available")
    func readClipboard_withoutUserdata_returnsFalse() {
        let handled = Ghostty.CallbackRouter.readClipboard(
            nil,
            location: GHOSTTY_CLIPBOARD_STANDARD,
            state: nil
        )

        #expect(!handled)
    }

    @Test("runtimeConfig read clipboard callback can invoke the helper path")
    func runtimeConfig_readClipboardCallback_invokesHelperPath() {
        let userdataPointer = UnsafeMutableRawPointer(bitPattern: 0x1)!
        let config = Ghostty.CallbackRouter.runtimeConfig(userdataPointer: userdataPointer)

        let handled = config.read_clipboard_cb(nil, GHOSTTY_CLIPBOARD_STANDARD, nil)

        #expect(!handled)
    }
}
