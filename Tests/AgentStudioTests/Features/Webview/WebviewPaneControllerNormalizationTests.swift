import Foundation
import Testing

@testable import AgentStudioWebview

@MainActor
@Suite
struct WebviewPaneControllerNormalizationTests {
    @Test
    func test_normalizeURLString_addsHttps() {
        #expect(
            WebviewPaneController.normalizeURLString("example.com") == "https://example.com"
        )
    }

    @Test
    func test_normalizeURLString_preservesExistingScheme() {
        #expect(
            WebviewPaneController.normalizeURLString("http://example.com") == "http://example.com"
        )
    }

    @Test
    func test_normalizeURLString_preservesAbout() {
        #expect(
            WebviewPaneController.normalizeURLString("about:blank") == "about:blank"
        )
    }

    @Test
    func test_normalizeURLString_emptyInput() {
        #expect(
            WebviewPaneController.normalizeURLString("") == "about:blank"
        )
    }

    @Test
    func test_normalizeURLString_trimsWhitespace() {
        #expect(
            WebviewPaneController.normalizeURLString("  github.com  ") == "https://github.com"
        )
    }

    @Test
    func test_normalizeURLString_preservesData() {
        #expect(
            WebviewPaneController.normalizeURLString("data:text/html,<h1>Hi</h1>")
                == "data:text/html,<h1>Hi</h1>"
        )
    }
}
