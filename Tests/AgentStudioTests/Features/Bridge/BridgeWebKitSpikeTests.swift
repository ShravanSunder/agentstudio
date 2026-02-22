import Foundation
import Testing
import WebKit

@testable import AgentStudio

// MARK: - Test Helpers

/// Captures `WKScriptMessage` bodies for assertion in content world message handler tests.
/// WebKit calls the delegate method on the main thread, so MainActor isolation is safe.
final class SpikeMessageHandler: NSObject, WKScriptMessageHandler {
    private let lock = NSLock()
    nonisolated(unsafe) private var storage: [Any] = []

    var receivedMessages: [Any] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        lock.lock()
        storage.append(message.body)
        lock.unlock()
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
extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    final class BridgeWebKitSpikeTests {

    // MARK: - Item 1: WKContentWorld creation and identity

    /// Verify `WKContentWorld.world(name:)` returns a non-nil world,
    /// and calling it twice with the same name returns the same instance.
    @Test
    func test_contentWorld_sameNameReturnsSameWorld() async {
        guard isWebKitSpikeModeEnabled() else { return }
        // Arrange
        let worldA = WKContentWorld.world(name: "agentStudioBridge")
        let worldB = WKContentWorld.world(name: "agentStudioBridge")

        // Assert -- same name should return the same (identical) world object
        #expect(
            worldA === worldB,
            "WKContentWorld.world(name:) with the same name should return the identical object"
        )
    }

    /// Verify different names produce different worlds.
    @Test
    func test_contentWorld_differentNamesProduceDifferentWorlds() async {
        guard isWebKitSpikeModeEnabled() else { return }
        // Arrange
        let worldA = WKContentWorld.world(name: "agentStudioBridge")
        let worldC = WKContentWorld.world(name: "differentWorld")

        // Assert
        #expect(!(worldA === worldC), "Different content world names should produce different world objects")
    }

    // MARK: - Item 2: callJavaScript with content world targeting

    /// Verify that callJavaScript in one content world cannot see globals
    /// set in another content world (JS namespace isolation).
    ///
    /// Strategy: Set a global in bridge world, then try to read it from page world
    /// via postMessage. If isolation works, page world won't see the variable.
    @Test
    func test_callJavaScript_contentWorldIsolation_globalsDoNotLeak() async throws {
        guard isWebKitSpikeModeEnabled() else { return }
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
        await settleAsyncCallbacks()

        // Read from bridge world -- should see it
        _ = try await page.callJavaScript(
            "window.webkit.messageHandlers.bridgeProbe.postMessage(window.__spikeVar || 'NOT_FOUND')",
            contentWorld: bridgeWorld
        )
        let sawBridgeMessage = await waitForMessageCount(bridgeHandler, atLeast: 1)
        #expect(sawBridgeMessage, "Expected bridge world probe message")

        // Read from page world -- should NOT see it
        _ = try await page.callJavaScript(
            "window.webkit.messageHandlers.pageProbe.postMessage(window.__spikeVar || 'NOT_FOUND')"
            // no contentWorld = page world
        )
        let sawPageMessage = await waitForMessageCount(pageHandler, atLeast: 1)
        #expect(sawPageMessage, "Expected page world probe message")

        // Assert
        #expect(bridgeHandler.receivedMessages.count == 1)
        #expect(
            bridgeHandler.receivedMessages.first as? String == "bridge-only",
            "Bridge world should see its own global variable")

        #expect(pageHandler.receivedMessages.count == 1)
        #expect(
            pageHandler.receivedMessages.first as? String == "NOT_FOUND",
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
    @Test
    func test_userScript_contentWorldInjection_isolatedFromPageWorld() async throws {
        guard isWebKitSpikeModeEnabled() else { return }
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
        let sawBridgeMessage = await waitForMessageCount(bridgeHandler, atLeast: 1)
        #expect(sawBridgeMessage, "Expected bridge world script-injection probe message")

        // Read flag from page world
        _ = try await page.callJavaScript(
            "window.webkit.messageHandlers.pageProbe.postMessage(String(window.__testFlag))"
            // no contentWorld = page world
        )
        let sawPageMessage = await waitForMessageCount(pageHandler, atLeast: 1)
        #expect(sawPageMessage, "Expected page world script-injection probe message")

        // Assert -- bridge world should see the flag
        #expect(bridgeHandler.receivedMessages.count == 1)
        #expect(
            bridgeHandler.receivedMessages.first as? String == "true",
            "WKUserScript injected with `in: world` should set __testFlag in bridge world")

        // Assert -- page world should NOT see the flag
        #expect(pageHandler.receivedMessages.count == 1)
        #expect(
            pageHandler.receivedMessages.first as? String == "undefined",
            "Page world should NOT see __testFlag set by bridge-world WKUserScript (isolation)")
    }

    // MARK: - Item 4: Message handler scoped to content world

    /// Verify that a message handler registered in a specific content world
    /// receives messages posted from that world.
    ///
    /// Design doc section 11.1 layer 2: "Only bridge-world scripts can post
    /// to the rpc handler."
    @Test
    func test_messageHandler_bridgeWorldCanPost() async throws {
        guard isWebKitSpikeModeEnabled() else { return }
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
        let sawMessage = await waitForMessageCount(handler, atLeast: 1)
        #expect(sawMessage, "Expected bridge-world handler message")

        // Assert -- handler received the message
        #expect(handler.receivedMessages.count == 1, "Message posted from bridge world should reach the handler")
        #expect(handler.receivedMessages.first as? String == "hello", "Message body should be the posted value")
    }

    /// Verify that the page world cannot post to a message handler registered
    /// in a different content world.
    ///
    /// The handler `rpc` is only registered in the bridge world. Page world
    /// should not be able to access `window.webkit.messageHandlers.rpc`.
    @Test
    func test_messageHandler_pageWorldCannotAccessBridgeHandler() async throws {
        guard isWebKitSpikeModeEnabled() else { return }
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
        await settleAsyncCallbacks()

        // Assert -- handler should NOT have received a message from page world
        #expect(
            handler.receivedMessages.isEmpty,
            "Page world should NOT be able to post to a bridge-world-scoped message handler")
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
            await Task.yield()
        }
        try #require(!page.isLoading, "Page did not finish loading within \(timeout)")
        await settleAsyncCallbacks(turns: 40)
    }

    private func waitForMessageCount(
        _ handler: SpikeMessageHandler,
        atLeast expectedCount: Int,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if handler.receivedMessages.count >= expectedCount {
                return true
            }
            await Task.yield()
        }
        return handler.receivedMessages.count >= expectedCount
    }

    private func settleAsyncCallbacks(turns: Int = 50) async {
        for _ in 0..<turns {
            await Task.yield()
        }
    }

    private func isWebKitSpikeModeEnabled() -> Bool {
        ProcessInfo.processInfo.environment["AGENT_STUDIO_WEBKIT_SPIKE_MODE"] == "on"
    }
}

}
