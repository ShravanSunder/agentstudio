import Testing

@testable import AgentStudio

@Suite("TerminalSurfaceAction")
struct TerminalSurfaceActionTests {
    @Test("binding action string serialization matches Ghostty bindings")
    func bindingActionStringSerializationMatchesGhosttyBindings() {
        let cases: [(TerminalSurfaceAction, String)] = [
            (.copyToClipboard, "copy_to_clipboard"),
            (.pasteFromClipboard, "paste_from_clipboard"),
            (.selectAll, "select_all"),
            (.scrollToBottom, "scroll_to_bottom"),
            (.scrollToRow(42), "scroll_to_row:42"),
            (.startSearch, "start_search"),
            (.search("needle"), "search:needle"),
            (.navigateSearch(.next), "navigate_search:next"),
            (.navigateSearch(.previous), "navigate_search:previous"),
            (.endSearch, "end_search"),
        ]

        for (action, expectedString) in cases {
            #expect(action.bindingActionString == expectedString)
        }
    }
}
