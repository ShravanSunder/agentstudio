import Testing

@testable import AgentStudio

@MainActor
@Suite("Empty arrangement placeholder")
struct EmptyArrangementPlaceholderTests {
    @Test
    func placeholderCopyDoesNotAdvertiseShortcut() {
        #expect(EmptyArrangementPlaceholderView.title == "No panes visible")
        #expect(!EmptyArrangementPlaceholderView.title.contains("⌘"))
        #expect(!EmptyArrangementPlaceholderView.title.localizedCaseInsensitiveContains("press"))
    }
}
