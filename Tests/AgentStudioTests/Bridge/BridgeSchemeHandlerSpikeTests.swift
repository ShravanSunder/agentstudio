import WebKit
import XCTest

@testable import AgentStudio

// MARK: - Spike Scheme Handler

/// Minimal URLSchemeHandler that serves a static HTML page.
/// Purpose: verify the AsyncStream-based URL scheme handler protocol
/// works with the WebPage API and custom `agentstudio://` scheme.
///
/// API findings from this spike:
/// - `AsyncThrowingStream` is required (not `AsyncStream`) because the
///   protocol demands `Failure == any Error`, while `AsyncStream.Failure`
///   is `Never`.
/// - The method signature is `reply(for:)` (confirmed by compiler).
/// - `URLScheme` initializer is failable: `URLScheme("agentstudio")!`.
private struct SpikeSchemeHandler: URLSchemeHandler {
    func reply(for request: URLRequest) -> some AsyncSequence<URLSchemeTaskResult, any Error> {
        AsyncThrowingStream<URLSchemeTaskResult, any Error> { continuation in
            let html = "<html><head><title>Spike Test</title></head><body>OK</body></html>"
            let data = Data(html.utf8)
            guard let url = request.url else {
                continuation.finish()
                return
            }
            continuation.yield(
                .response(
                    URLResponse(
                        url: url,
                        mimeType: "text/html",
                        expectedContentLength: data.count,
                        textEncodingName: "utf-8"
                    )))
            continuation.yield(.data(data))
            continuation.finish()
        }
    }
}

// MARK: - Tests

@MainActor
final class BridgeSchemeHandlerSpikeTests: XCTestCase {

    // MARK: - Scheme Handler Serves HTML

    /// Verify that a custom `agentstudio://` scheme handler registered on
    /// WebPage.Configuration can serve an HTML page. The page URL, title,
    /// and loading state are checked after load completes.
    func test_customSchemeHandler_servesHTMLPage_andTitleIsReadable() async throws {
        // Arrange — build configuration with custom scheme handler
        let page = try makePageWithSpikeHandler()

        // Act — load a page on the custom scheme
        let testURL = URL(string: "agentstudio://app/test.html")!
        _ = page.load(testURL)
        try await waitForPageLoad(page)

        // Assert — scheme handler served the page
        XCTAssertEqual(
            page.url?.absoluteString, "agentstudio://app/test.html",
            "Page URL should reflect the custom scheme URL")
        XCTAssertFalse(
            page.isLoading,
            "Page should finish loading")
        XCTAssertEqual(
            page.title, "Spike Test",
            "page.title should reflect <title> from scheme handler HTML")
    }

    // MARK: - JavaScript Evaluation

    /// Spike finding: `callJavaScript("document.title")` returns nil in a
    /// headless (no-window) test context, even though `page.title` works.
    /// This test documents that behavior so downstream code knows to use
    /// `page.title` for title access in tests, and `callJavaScript` for
    /// runtime use where a window is present.
    func test_callJavaScript_returnsNil_inHeadlessContext() async throws {
        // Arrange
        let page = try makePageWithSpikeHandler()
        let testURL = URL(string: "agentstudio://app/test.html")!
        _ = page.load(testURL)
        try await waitForPageLoad(page)

        // Act — attempt JavaScript evaluation without a window
        let jsResult = try await page.callJavaScript("document.title")

        // Assert — nil in headless context (spike finding)
        XCTAssertNil(
            jsResult,
            "Spike finding: callJavaScript returns nil without a window/view host")
        // But page.title works
        XCTAssertEqual(
            page.title, "Spike Test",
            "page.title works even without a window")
    }

    // MARK: - Helpers

    private func makePageWithSpikeHandler() throws -> WebPage {
        var config = WebPage.Configuration()
        config.websiteDataStore = .nonPersistent()
        config.urlSchemeHandlers[URLScheme("agentstudio")!] = SpikeSchemeHandler()

        return WebPage(
            configuration: config,
            navigationDecider: WebviewNavigationDecider(),
            dialogPresenter: WebviewDialogHandler()
        )
    }

    private func waitForPageLoad(_ page: WebPage) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if !page.isLoading { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        // Settle time for WebKit internals after isLoading flips
        try await Task.sleep(for: .milliseconds(200))
    }
}
