import Foundation
import Testing
import WebKit

@testable import AgentStudio

/// Integration tests for the BridgePaneController's assembled transport pipeline.
///
/// These tests verify that the controller's components (WebPage, BridgeSchemeHandler,
/// RPCMessageHandler, RPCRouter, BridgeBootstrap) work together correctly:
///
/// 1. Bridge.ready handshake gating — `isBridgeReady` transitions and idempotency (§4.5)
/// 2. Scheme handler serves HTML — `loadApp()` loads content from `agentstudio://app/index.html`
/// 3. Content world isolation — page world cannot see `window.__bridgeInternal`
///
/// Unlike the spike tests which exercise raw WebKit APIs, these tests exercise
/// the fully-assembled BridgePaneController and its real dependencies.
@MainActor
@Suite(.serialized)
final class BridgeTransportIntegrationTests {

    // MARK: - Test 1: Bridge.ready handshake gating

    /// Verify that `isBridgeReady` starts false, becomes true after `handleBridgeReady()`,
    /// and remains true on repeated calls (idempotent gating per §4.5 line 246).
    @Test
    func test_bridgeReady_gatesAndIsIdempotent() {
        // Arrange — create a controller with default bridge pane state
        let paneId = UUID()
        let state = BridgePaneState(panelKind: .diffViewer, source: nil)
        let controller = BridgePaneController(paneId: paneId, state: state)

        // Assert — before handshake, bridge is not ready
        #expect(!(controller.isBridgeReady), "isBridgeReady should be false before bridge.ready handshake")

        // Act — first handshake call
        controller.handleBridgeReady()

        // Assert — after first call, bridge is ready
        #expect(controller.isBridgeReady, "isBridgeReady should be true after handleBridgeReady()")

        // Act — second handshake call (idempotent, should be a no-op)
        controller.handleBridgeReady()

        // Assert — still true, no crash, no state change
        #expect(
            controller.isBridgeReady,
            "isBridgeReady should remain true after repeated handleBridgeReady() calls (idempotent)")

        // Cleanup
        controller.teardown()
    }

    /// Verify that `teardown()` resets `isBridgeReady` to false.
    @Test
    func test_teardown_resetsBridgeReady() {
        // Arrange — create controller and trigger handshake
        let paneId = UUID()
        let state = BridgePaneState(panelKind: .diffViewer, source: nil)
        let controller = BridgePaneController(paneId: paneId, state: state)
        controller.handleBridgeReady()
        #expect(controller.isBridgeReady)

        // Act
        controller.teardown()

        // Assert — bridge state is reset
        #expect(!(controller.isBridgeReady), "teardown() should reset isBridgeReady to false")
    }

    /// Verify that transport pushes execute through the bridge world `callJavaScript`
    /// path and emit `__bridge_push` events into the page event stream.
    @Test
    func test_pushJSON_dispatches_to_bridge_internal_applyEnvelope() async throws {
        // Arrange
        struct PushProbeMethod: RPCMethod {
            struct Params: Decodable {}

            typealias Result = RPCNoResponse
            static let method = "agent.pushProbe"
        }

        let paneId = UUID()
        let state = BridgePaneState(panelKind: .diffViewer, source: nil)
        let controller = BridgePaneController(
            paneId: paneId,
            state: state
        )

        actor SendableCounter {
            private var value: Int

            init(_ value: Int) {
                self.value = value
            }

            func increment() {
                value += 1
            }

            func get() -> Int {
                value
            }
        }

        let pushProbeCallCount = SendableCounter(0)
        var transportErrorCode: Int?
        controller.router.register(method: PushProbeMethod.self) { _ in
            await pushProbeCallCount.increment()
            return nil
        }
        controller.router.onError = { code, _, _ in
            transportErrorCode = code
        }

        controller.loadApp()
        try await waitForPageLoad(controller.page)
        controller.handleBridgeReady()

        let bridgeWorld = WKContentWorld.world(name: "agentStudioBridge")
        let installProbeScript = """
            document.addEventListener('__bridge_push', function() {
                window.webkit.messageHandlers.rpc.postMessage(JSON.stringify({
                    jsonrpc: '2.0',
                    method: 'agent.pushProbe'
                }));
            });
            """
        _ = try await controller.page.callJavaScript(installProbeScript, contentWorld: bridgeWorld)

        // Act — mutate diff state to force a non-batch state push
        controller.paneState.diff.status = .loading

        // Assert — at least one bridge push should replay through the probe method
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if await pushProbeCallCount.get() > 0 {
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(await pushProbeCallCount.get() > 0)
        #expect(transportErrorCode == nil)

        controller.teardown()
    }

    // MARK: - Test 2: Scheme handler serves app HTML

    /// Verify that `loadApp()` triggers the BridgeSchemeHandler to serve content
    /// from `agentstudio://app/index.html`, producing a loaded page with the expected
    /// URL and title.
    @Test
    func test_schemeHandler_servesAppHtml() async throws {
        // Arrange — create controller and load the app
        let paneId = UUID()
        let state = BridgePaneState(panelKind: .diffViewer, source: nil)
        let controller = BridgePaneController(paneId: paneId, state: state)

        // Act — load the bundled React app URL
        controller.loadApp()
        try await waitForPageLoad(controller.page)

        // Assert — page loaded from custom scheme with expected URL
        #expect(
            controller.page.url?.absoluteString == "agentstudio://app/index.html",
            "loadApp() should navigate to agentstudio://app/index.html")
        #expect(!(controller.page.isLoading), "Page should finish loading after loadApp()")

        // Assert — BridgeSchemeHandler serves the page (Phase 1 stub returns "Bridge" title)
        #expect(
            controller.page.title == "Bridge",
            "BridgeSchemeHandler should serve HTML with <title>Bridge</title> for app routes")

        // Cleanup
        controller.teardown()
    }

    // MARK: - Test 3: Content world isolation

    /// Verify that `window.__bridgeInternal` (installed by BridgeBootstrap in the bridge
    /// content world) is NOT visible from the page world.
    ///
    /// This confirms content world isolation: the bootstrap script runs only in the bridge
    /// world, and page-world JavaScript cannot access bridge internals.
    ///
    /// Strategy: Replicate the BridgePaneController's WebPage setup (same bootstrap script,
    /// same scheme handler, same content world) but add a page-world probe handler for
    /// verification. This is necessary because `WebPage` does not expose its configuration
    /// post-creation, so we cannot add a probe handler to an existing controller's page.
    ///
    /// The test verifies the same isolation property: after the bootstrap script injects
    /// `__bridgeInternal` in the bridge world, page-world JS cannot see it.
    @Test
    func test_pageWorld_cannotAccessBridgeInternal() async throws {
        // Arrange — build the same configuration as BridgePaneController, plus a page-world probe
        let paneId = UUID()
        let bridgeWorld = WKContentWorld.world(name: "agentStudioBridge")
        let pageProbe = IntegrationTestMessageHandler()

        var config = WebPage.Configuration()
        config.websiteDataStore = .nonPersistent()

        // Same message handler setup as BridgePaneController
        let messageHandler = RPCMessageHandler()
        config.userContentController.add(
            messageHandler,
            contentWorld: bridgeWorld,
            name: "rpc"
        )

        // Same bootstrap script as BridgePaneController
        let bootstrapScript = WKUserScript(
            source: BridgeBootstrap.generateScript(bridgeNonce: UUID().uuidString, pushNonce: UUID().uuidString),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: bridgeWorld
        )
        config.userContentController.addUserScript(bootstrapScript)

        // Same scheme handler as BridgePaneController
        if let scheme = URLScheme("agentstudio") {
            config.urlSchemeHandlers[scheme] = BridgeSchemeHandler(paneId: paneId)
        }

        // Additional: page-world probe handler for test verification
        config.userContentController.add(pageProbe, contentWorld: .page, name: "pageProbe")

        let page = WebPage(
            configuration: config,
            navigationDecider: BridgeNavigationDecider(),
            dialogPresenter: WebviewDialogHandler()
        )

        // Act — load the app (triggers bootstrap script injection in bridge world)
        _ = page.load(URL(string: "agentstudio://app/index.html")!)
        try await waitForPageLoad(page)

        // Execute JS in page world (no contentWorld = page world) to check isolation
        _ = try await page.callJavaScript(
            "window.webkit.messageHandlers.pageProbe.postMessage(typeof window.__bridgeInternal)"
            // no contentWorld parameter → runs in page world
        )
        try await Task.sleep(for: .milliseconds(500))

        // Assert — page world should see __bridgeInternal as undefined
        #expect(pageProbe.receivedMessages.count == 1, "Page world probe should receive exactly one message")
        #expect(
            pageProbe.receivedMessages.first as? String == "undefined",
            "window.__bridgeInternal should be 'undefined' in page world (content world isolation)")
    }

    // MARK: - Helpers

    /// Wait for page load to complete, throwing on timeout.
    /// Polls `page.isLoading` and enforces a hard deadline.
    private func waitForPageLoad(_ page: WebPage, timeout: Duration = .seconds(5)) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if !page.isLoading { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try #require(!page.isLoading, "Page did not finish loading within \(timeout)")
        // Settle time for WebKit internals after isLoading flips
        try await Task.sleep(for: .milliseconds(200))
    }
}

// MARK: - Test Message Handler

/// Captures `WKScriptMessage` bodies for assertion in integration tests.
/// Same pattern as the spike tests' `SpikeMessageHandler` but scoped to integration tests.
final class IntegrationTestMessageHandler: NSObject, WKScriptMessageHandler {
    // Using nonisolated(unsafe) because WKScriptMessageHandler protocol method is nonisolated,
    // but it's called on the main thread. The property is read in test assertions on main thread.
    nonisolated(unsafe) var receivedMessages: [Any] = []

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        receivedMessages.append(message.body)
    }
}
