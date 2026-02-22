import Foundation
import Testing
import WebKit

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

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    final class BridgeSchemeHandlerSpikeTests {

    // MARK: - Scheme Handler Serves HTML

    /// Verify that a custom `agentstudio://` scheme handler registered on
    /// WebPage.Configuration can serve an HTML page. The page URL, title,
    /// and loading state are checked after load completes.
    @Test
    func test_customSchemeHandler_servesHTMLPage_andTitleIsReadable() async throws {
        // Arrange — build configuration with custom scheme handler
        let page = try makePageWithSpikeHandler()

        // Act — load a page on the custom scheme
        let testURL = URL(string: "agentstudio://app/test.html")!
        _ = page.load(testURL)
        try await waitForPageLoad(page)
        let didResolveTitle = await waitForTitle(page, equals: "Spike Test")

        // Assert — scheme handler served the page
        #expect(
            page.url?.absoluteString == "agentstudio://app/test.html",
            "Page URL should reflect the custom scheme URL")
        #expect(!(page.isLoading), "Page should finish loading")
        #expect(didResolveTitle, "page.title should resolve after the custom-scheme page load")
        #expect(page.title == "Spike Test", "page.title should reflect <title> from scheme handler HTML")
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
            await Task.yield()
        }
        try #require(!page.isLoading, "Page did not finish loading within timeout")
    }

    private func waitForTitle(
        _ page: WebPage,
        equals expectedTitle: String,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if page.title == expectedTitle {
                return true
            }
            await Task.yield()
        }
        return page.title == expectedTitle
    }
    }
}
