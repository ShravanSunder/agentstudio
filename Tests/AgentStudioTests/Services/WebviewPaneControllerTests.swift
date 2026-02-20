import XCTest

@testable import AgentStudio

@MainActor
final class WebviewPaneControllerTests: XCTestCase {

    // MARK: - Init

    func test_init_createsPage_fromState() {
        // Arrange
        let state = WebviewState(url: URL(string: "https://github.com")!, title: "GitHub")

        // Act
        let controller = WebviewPaneController(paneId: UUID(), state: state)

        // Assert
        XCTAssertTrue(controller.showNavigation)
        XCTAssertNotNil(controller.page)
    }

    func test_init_aboutBlank_doesNotLoad() {
        // Arrange
        let state = WebviewState(url: URL(string: "about:blank")!)

        // Act
        let controller = WebviewPaneController(paneId: UUID(), state: state)

        // Assert — page exists but url is nil (nothing loaded)
        XCTAssertNil(controller.url)
    }

    func test_init_respectsShowNavigation() {
        // Arrange
        let state = WebviewState(url: URL(string: "https://example.com")!, showNavigation: false)

        // Act
        let controller = WebviewPaneController(paneId: UUID(), state: state)

        // Assert
        XCTAssertFalse(controller.showNavigation)
    }

    // MARK: - Snapshot

    func test_snapshot_capturesState() {
        // Arrange
        let controller = makeController()

        // Act
        let snapshot = controller.snapshot()

        // Assert
        XCTAssertTrue(snapshot.showNavigation)
        XCTAssertNotNil(snapshot.url)
    }

    func test_snapshot_aboutBlank_fallback() {
        // Arrange — controller with about:blank (nothing loaded → url is nil)
        let controller = WebviewPaneController(
            paneId: UUID(),
            state: WebviewState(url: URL(string: "about:blank")!)
        )

        // Act
        let snapshot = controller.snapshot()

        // Assert — nil url falls back to about:blank
        XCTAssertEqual(snapshot.url.absoluteString, "about:blank")
    }

    // MARK: - URL Normalization

    func test_normalizeURLString_addsHttps() {
        XCTAssertEqual(
            WebviewPaneController.normalizeURLString("example.com"),
            "https://example.com"
        )
    }

    func test_normalizeURLString_preservesExistingScheme() {
        XCTAssertEqual(
            WebviewPaneController.normalizeURLString("http://example.com"),
            "http://example.com"
        )
    }

    func test_normalizeURLString_preservesAbout() {
        XCTAssertEqual(
            WebviewPaneController.normalizeURLString("about:blank"),
            "about:blank"
        )
    }

    func test_normalizeURLString_emptyInput() {
        XCTAssertEqual(
            WebviewPaneController.normalizeURLString(""),
            "about:blank"
        )
    }

    func test_normalizeURLString_trimsWhitespace() {
        XCTAssertEqual(
            WebviewPaneController.normalizeURLString("  github.com  "),
            "https://github.com"
        )
    }

    func test_normalizeURLString_preservesData() {
        XCTAssertEqual(
            WebviewPaneController.normalizeURLString("data:text/html,<h1>Hi</h1>"),
            "data:text/html,<h1>Hi</h1>"
        )
    }

    // MARK: - Helpers

    private func makeController() -> WebviewPaneController {
        WebviewPaneController(
            paneId: UUID(),
            state: WebviewState(url: URL(string: "https://example.com")!)
        )
    }
}
