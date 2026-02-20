import WebKit
import XCTest

@testable import AgentStudio

// MARK: - Test Helpers

/// Captures `WKScriptMessage` bodies for assertion in content world message handler tests.
/// WebKit calls the delegate method on the main thread, so MainActor isolation is safe.
final class SpikeMessageHandler: NSObject, WKScriptMessageHandler {
    // Using nonisolated(unsafe) because WKScriptMessageHandler is called on main thread
    // but the protocol method is nonisolated.
    nonisolated(unsafe) var receivedMessages: [Any] = []

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        receivedMessages.append(message.body)
    }
}

/// Minimal URLSchemeHandler that serves a blank HTML page.
/// Used for tests that need a proper document context.
private struct BlankPageSchemeHandler: URLSchemeHandler {
    func reply(for request: URLRequest) -> some AsyncSequence<URLSchemeTaskResult, any Error> {
        AsyncThrowingStream<URLSchemeTaskResult, any Error> { continuation in
            let html = "<html><head><title>Spike Blank</title></head><body></body></html>"
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

/// Verification spike for bridge-specific WebKit APIs.
///
/// Validates design doc section 16 items 1-4 before Phase 1 implementation:
/// 1. WKContentWorld creation and identity
/// 2. callJavaScript with arguments and content world targeting
/// 3. WKUserScript with content world injection isolation
/// 4. Message handler scoped to content world
///
/// These are NOT unit tests -- they exercise real WebKit instances.
///
/// ## Spike Finding: callJavaScript return values
///
/// `WebPage.callJavaScript` returns nil in headless test contexts (no window host).
/// This is a WebKit for SwiftUI limitation: the underlying WKWebView needs to be
/// hosted in a view hierarchy attached to a window for JS evaluation to return values.
/// However, `callJavaScript` DOES execute the JS code -- side effects like
/// `postMessage` work correctly. Tests use message handlers as verification probes
/// instead of relying on return values.
///
/// This does NOT affect production use, where WebPages are always hosted in a
/// `WebView` inside a window.
@MainActor
final class BridgeWebKitSpikeTests: XCTestCase {

    // MARK: - Item 1: WKContentWorld creation and identity

    /// Verify `WKContentWorld.world(name:)` returns a non-nil world,
    /// and calling it twice with the same name returns the same instance.
    func test_contentWorld_sameNameReturnsSameWorld() {
        // Arrange
        let worldA = WKContentWorld.world(name: "agentStudioBridge")
        let worldB = WKContentWorld.world(name: "agentStudioBridge")

        // Assert -- same name should return the same (identical) world object
        XCTAssertNotNil(worldA)
        XCTAssertTrue(
            worldA === worldB,
            "WKContentWorld.world(name:) with the same name should return the identical object")
    }

    /// Verify different names produce different worlds.
    func test_contentWorld_differentNamesProduceDifferentWorlds() {
        // Arrange
        let worldA = WKContentWorld.world(name: "agentStudioBridge")
        let worldC = WKContentWorld.world(name: "differentWorld")

        // Assert
        XCTAssertFalse(
            worldA === worldC,
            "Different content world names should produce different world objects")
    }

    // MARK: - Item 2: callJavaScript with content world targeting

    /// Verify that `callJavaScript` executes in a specific content world and
    /// that arguments are passed as JS local variables.
    ///
    /// Since callJavaScript returns nil in headless tests, we verify execution
    /// via a message handler: the JS code posts the argument value back to Swift.
    ///
    /// Design doc section 4.1 line 137: "Arguments become JS local variables."
    func test_callJavaScript_withArgumentsAndContentWorld_executesInWorld() async throws {
        // Arrange -- message handler in bridge world acts as verification probe
        let world = WKContentWorld.world(name: "testBridgeCallJS")
        let handler = SpikeMessageHandler()

        var config = WebPage.Configuration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(handler, contentWorld: world, name: "probe")
        config.urlSchemeHandlers[URLScheme("agentstudio")!] = BlankPageSchemeHandler()

        let page = WebPage(
            configuration: config,
            navigationDecider: WebviewNavigationDecider(),
            dialogPresenter: WebviewDialogHandler()
        )

        _ = page.load(URL(string: "agentstudio://app/blank.html")!)
        try await waitForPageLoad(page)

        // Act -- execute JS in content world with arguments, post result back
        _ = try await page.callJavaScript(
            "window.webkit.messageHandlers.probe.postMessage(String(value))",
            arguments: ["value": 42],
            contentWorld: world
        )
        try await Task.sleep(for: .milliseconds(300))

        // Assert -- message should contain the argument value
        XCTAssertEqual(
            handler.receivedMessages.count, 1,
            "callJavaScript with contentWorld should execute and postMessage should work")
        XCTAssertEqual(
            handler.receivedMessages.first as? String, "42",
            "Arguments passed to callJavaScript should be available as JS local variables")
    }

    /// Verify that callJavaScript in one content world cannot see globals
    /// set in another content world (JS namespace isolation).
    ///
    /// Strategy: Set a global in bridge world, then try to read it from page world
    /// via postMessage. If isolation works, page world won't see the variable.
    func test_callJavaScript_contentWorldIsolation_globalsDoNotLeak() async throws {
        // Arrange -- handlers in both worlds
        let bridgeWorld = WKContentWorld.world(name: "testBridgeIsolation")
        let bridgeHandler = SpikeMessageHandler()
        let pageHandler = SpikeMessageHandler()

        var config = WebPage.Configuration()
        config.websiteDataStore = .nonPersistent()
        // Register handler in bridge world
        config.userContentController.add(bridgeHandler, contentWorld: bridgeWorld, name: "bridgeProbe")
        // Register handler in page world
        config.userContentController.add(pageHandler, contentWorld: .page, name: "pageProbe")
        config.urlSchemeHandlers[URLScheme("agentstudio")!] = BlankPageSchemeHandler()

        let page = WebPage(
            configuration: config,
            navigationDecider: WebviewNavigationDecider(),
            dialogPresenter: WebviewDialogHandler()
        )

        _ = page.load(URL(string: "agentstudio://app/blank.html")!)
        try await waitForPageLoad(page)

        // Act -- set a global in bridge world
        _ = try await page.callJavaScript(
            "window.__spikeVar = 'bridge-only'",
            contentWorld: bridgeWorld
        )
        try await Task.sleep(for: .milliseconds(200))

        // Read from bridge world -- should see it
        _ = try await page.callJavaScript(
            "window.webkit.messageHandlers.bridgeProbe.postMessage(window.__spikeVar || 'NOT_FOUND')",
            contentWorld: bridgeWorld
        )
        try await Task.sleep(for: .milliseconds(200))

        // Read from page world -- should NOT see it
        _ = try await page.callJavaScript(
            "window.webkit.messageHandlers.pageProbe.postMessage(window.__spikeVar || 'NOT_FOUND')"
            // no contentWorld = page world
        )
        try await Task.sleep(for: .milliseconds(200))

        // Assert
        XCTAssertEqual(bridgeHandler.receivedMessages.count, 1)
        XCTAssertEqual(
            bridgeHandler.receivedMessages.first as? String, "bridge-only",
            "Bridge world should see its own global variable")

        XCTAssertEqual(pageHandler.receivedMessages.count, 1)
        XCTAssertEqual(
            pageHandler.receivedMessages.first as? String, "NOT_FOUND",
            "Page world should NOT see bridge world's global variable (isolation)")
    }

    // MARK: - Item 3: WKUserScript with content world injection

    /// Verify that a WKUserScript injected into a specific content world runs
    /// in that world and is isolated from the page world.
    ///
    /// Strategy: Inject a user script in bridge world that sets a global flag,
    /// then use message handlers in both worlds to verify the flag is only
    /// visible in the bridge world.
    ///
    /// Design doc section 11.2: WKUserScript takes content world in its initializer
    /// via the `in:` parameter label.
    func test_userScript_contentWorldInjection_isolatedFromPageWorld() async throws {
        // Arrange
        let world = WKContentWorld.world(name: "testBridgeUserScript")
        let bridgeHandler = SpikeMessageHandler()
        let pageHandler = SpikeMessageHandler()

        var config = WebPage.Configuration()
        config.websiteDataStore = .nonPersistent()

        // Inject user script in bridge world that sets a flag
        let script = WKUserScript(
            source: "window.__testFlag = true;",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: world
        )
        config.userContentController.addUserScript(script)

        // Register handlers in both worlds for verification
        config.userContentController.add(bridgeHandler, contentWorld: world, name: "bridgeProbe")
        config.userContentController.add(pageHandler, contentWorld: .page, name: "pageProbe")
        config.urlSchemeHandlers[URLScheme("agentstudio")!] = BlankPageSchemeHandler()

        let page = WebPage(
            configuration: config,
            navigationDecider: WebviewNavigationDecider(),
            dialogPresenter: WebviewDialogHandler()
        )

        // Act -- load page to trigger user script injection
        _ = page.load(URL(string: "agentstudio://app/blank.html")!)
        try await waitForPageLoad(page)

        // Read flag from bridge world
        _ = try await page.callJavaScript(
            "window.webkit.messageHandlers.bridgeProbe.postMessage(String(window.__testFlag))",
            contentWorld: world
        )
        try await Task.sleep(for: .milliseconds(300))

        // Read flag from page world
        _ = try await page.callJavaScript(
            "window.webkit.messageHandlers.pageProbe.postMessage(String(window.__testFlag))"
            // no contentWorld = page world
        )
        try await Task.sleep(for: .milliseconds(300))

        // Assert -- bridge world should see the flag
        XCTAssertEqual(bridgeHandler.receivedMessages.count, 1)
        XCTAssertEqual(
            bridgeHandler.receivedMessages.first as? String, "true",
            "WKUserScript injected with `in: world` should set __testFlag in bridge world")

        // Assert -- page world should NOT see the flag
        XCTAssertEqual(pageHandler.receivedMessages.count, 1)
        XCTAssertEqual(
            pageHandler.receivedMessages.first as? String, "undefined",
            "Page world should NOT see __testFlag set by bridge-world WKUserScript (isolation)")
    }

    // MARK: - Item 4: Message handler scoped to content world

    /// Verify that a message handler registered in a specific content world
    /// receives messages posted from that world.
    ///
    /// Design doc section 11.1 layer 2: "Only bridge-world scripts can post
    /// to the rpc handler."
    func test_messageHandler_bridgeWorldCanPost() async throws {
        // Arrange
        let world = WKContentWorld.world(name: "testBridgeMsgHandler")
        let handler = SpikeMessageHandler()

        var config = WebPage.Configuration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(handler, contentWorld: world, name: "rpc")

        let page = WebPage(
            configuration: config,
            navigationDecider: WebviewNavigationDecider(),
            dialogPresenter: WebviewDialogHandler()
        )

        _ = page.load(URL(string: "about:blank")!)
        try await waitForPageLoad(page)

        // Act -- post message FROM the bridge world
        _ = try await page.callJavaScript(
            "window.webkit.messageHandlers.rpc.postMessage('hello')",
            contentWorld: world
        )
        try await Task.sleep(for: .milliseconds(300))

        // Assert -- handler received the message
        XCTAssertEqual(
            handler.receivedMessages.count, 1,
            "Message posted from bridge world should reach the handler")
        XCTAssertEqual(
            handler.receivedMessages.first as? String, "hello",
            "Message body should be the posted value")
    }

    /// Verify that the page world cannot post to a message handler registered
    /// in a different content world.
    ///
    /// The handler `rpc` is only registered in the bridge world. Page world
    /// should not be able to access `window.webkit.messageHandlers.rpc`.
    func test_messageHandler_pageWorldCannotAccessBridgeHandler() async throws {
        // Arrange
        let world = WKContentWorld.world(name: "testBridgeMsgHandlerIsolation")
        let handler = SpikeMessageHandler()

        var config = WebPage.Configuration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(handler, contentWorld: world, name: "rpc")

        let page = WebPage(
            configuration: config,
            navigationDecider: WebviewNavigationDecider(),
            dialogPresenter: WebviewDialogHandler()
        )

        _ = page.load(URL(string: "about:blank")!)
        try await waitForPageLoad(page)

        // Act -- attempt to access the handler from page world using optional chaining
        // to avoid throwing if the handler doesn't exist
        _ = try? await page.callJavaScript(
            "window.webkit?.messageHandlers?.rpc?.postMessage('evil')"
            // no contentWorld = page world
        )
        try await Task.sleep(for: .milliseconds(300))

        // Assert -- handler should NOT have received a message from page world
        XCTAssertEqual(
            handler.receivedMessages.count, 0,
            "Page world should NOT be able to post to a bridge-world-scoped message handler")
    }

    /// Verify that message handler receives structured JSON data (not just strings).
    /// This validates the pattern used by RPCMessageHandler in the bridge design.
    func test_messageHandler_receivesJSONStringPayload() async throws {
        // Arrange
        let world = WKContentWorld.world(name: "testBridgeJSONMsg")
        let handler = SpikeMessageHandler()

        var config = WebPage.Configuration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(handler, contentWorld: world, name: "rpc")

        let page = WebPage(
            configuration: config,
            navigationDecider: WebviewNavigationDecider(),
            dialogPresenter: WebviewDialogHandler()
        )

        _ = page.load(URL(string: "about:blank")!)
        try await waitForPageLoad(page)

        // Act -- post a JSON string (the pattern used by the bridge relay)
        _ = try await page.callJavaScript(
            """
            window.webkit.messageHandlers.rpc.postMessage(
                JSON.stringify({ jsonrpc: "2.0", method: "test.ping", params: {} })
            )
            """,
            contentWorld: world
        )
        try await Task.sleep(for: .milliseconds(300))

        // Assert -- handler should receive the JSON string
        XCTAssertEqual(handler.receivedMessages.count, 1)
        let body = handler.receivedMessages.first as? String
        XCTAssertNotNil(body, "postMessage with JSON.stringify should deliver a String body")
        if let body {
            let parsed = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]
            XCTAssertEqual(
                parsed?["method"] as? String, "test.ping",
                "JSON string payload should be parseable and contain the method")
        }
    }

    // MARK: - Helpers

    /// Create a WebPage with a scheme handler for tests that need a real
    /// HTML document.
    private func makeSchemeServedPage() -> WebPage {
        var config = WebPage.Configuration()
        config.websiteDataStore = .nonPersistent()
        config.urlSchemeHandlers[URLScheme("agentstudio")!] = BlankPageSchemeHandler()
        return WebPage(
            configuration: config,
            navigationDecider: WebviewNavigationDecider(),
            dialogPresenter: WebviewDialogHandler()
        )
    }

    /// Wait for page load to complete, throwing on timeout.
    /// Polls `page.isLoading` and enforces a hard deadline so tests
    /// fail explicitly rather than asserting against an unready page.
    private func waitForPageLoad(_ page: WebPage, timeout: Duration = .seconds(5)) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if !page.isLoading { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard !page.isLoading else {
            XCTFail("Page did not finish loading within \(timeout)")
            return
        }
        // Settle time for WebKit internals after isLoading flips
        try await Task.sleep(for: .milliseconds(200))
    }
}
