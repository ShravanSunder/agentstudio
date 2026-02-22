import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WebviewPaneControllerTests {

    private func makeController() -> WebviewPaneController {
        WebviewPaneController(
            paneId: UUID(),
            state: WebviewState(url: URL(string: "https://example.com")!)
        )
    }

    // MARK: - Init

    @Test
    func test_init_createsPage_fromState() {
        // Arrange
        let state = WebviewState(url: URL(string: "https://github.com")!, title: "GitHub")

        // Act
        let controller = WebviewPaneController(paneId: UUID(), state: state)

        // Assert
        #expect(controller.showNavigation)
        #expect(controller.url?.scheme == state.url.scheme)
        #expect(controller.url?.host() == state.url.host())
    }

    @Test
    func test_init_aboutBlank_doesNotLoad() {
        // Arrange
        let state = WebviewState(url: URL(string: "about:blank")!)

        // Act
        let controller = WebviewPaneController(paneId: UUID(), state: state)

        // Assert — page exists but url is nil (nothing loaded)
        #expect(controller.url == nil)
    }

    @Test
    func test_init_respectsShowNavigation() {
        // Arrange
        let state = WebviewState(url: URL(string: "https://example.com")!, showNavigation: false)

        // Act
        let controller = WebviewPaneController(paneId: UUID(), state: state)

        // Assert
        #expect(!controller.showNavigation)
    }

    // MARK: - Snapshot

    @Test
    func test_snapshot_capturesState() {
        // Arrange
        let controller = makeController()

        // Act
        let snapshot = controller.snapshot()

        // Assert
        #expect(snapshot.showNavigation)
        #expect(snapshot.url.host() == "example.com")
    }

    @Test
    func test_snapshot_aboutBlank_fallback() {
        // Arrange — controller with about:blank (nothing loaded → url is nil)
        let controller = WebviewPaneController(
            paneId: UUID(),
            state: WebviewState(url: URL(string: "about:blank")!)
        )

        // Act
        let snapshot = controller.snapshot()

        // Assert — nil url falls back to about:blank
        #expect(snapshot.url.absoluteString == "about:blank")
    }

    // MARK: - URL Normalization

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
