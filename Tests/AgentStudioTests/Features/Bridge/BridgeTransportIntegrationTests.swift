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
extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    final class BridgeTransportIntegrationTests {

    // MARK: - Test 1: Bridge.ready handshake gating

    /// Verify that `isBridgeReady` starts false, becomes true after `handleBridgeReady()`,
    /// and remains true on repeated calls (idempotent gating per §4.5 line 246).
    @Test
    func test_bridgeReady_gatesAndIsIdempotent() async {
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
    func test_teardown_resetsBridgeReady() async {
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

    /// Verify that state mutation attempts push transport and updates connection health
    /// when JavaScript transport is unavailable.
    @Test
    func test_pushJSON_transportFailure_setsConnectionHealthError() async throws {
        let paneId = UUID()
        let state = BridgePaneState(panelKind: .diffViewer, source: nil)
        let controller = BridgePaneController(paneId: paneId, state: state)

        // Arrange — enable push plans without loading a page.
        controller.handleBridgeReady()

        // Act — mutate diff state to force a push attempt.
        controller.paneState.diff.setStatus(.loading)

        // Assert — transport failure path is surfaced via connection health.
        let didObserveTransportFailure = await waitUntil {
            controller.paneState.connection.health == .error
        }
        #expect(didObserveTransportFailure, "Expected connection health to reflect transport failure")

        controller.teardown()
    }

    /// Verify request responses with IDs are emitted as JSON-RPC response envelopes.
    /// This validates the controller+router response pipeline without relying on WebKit
    /// event wiring (covered by spike tests).
    @Test
    func test_requestWithId_emitsBridgeResponseEvent() async throws {
        struct EchoMethod: RPCMethod {
            struct Params: Decodable, Sendable {
                let text: String
            }

            struct ResultPayload: Codable, Sendable {
                let echoed: String
            }

            typealias Result = ResultPayload
            static let method = "agent.responseEcho"
        }

        struct RPCSuccessEnvelope: Decodable, Sendable {
            let jsonrpc: String
            let id: Int64
            let result: EchoMethod.ResultPayload
        }

        actor ResponseCaptureBox {
            private var payload: String?

            func set(_ value: String) {
                payload = value
            }

            func get() -> String? {
                payload
            }
        }

        let paneId = UUID()
        let state = BridgePaneState(panelKind: .diffViewer, source: nil)
        let controller = BridgePaneController(paneId: paneId, state: state)
        let capturedResponse = ResponseCaptureBox()

        controller.router.register(method: EchoMethod.self) { params in
            .init(echoed: params.text)
        }
        controller.router.onResponse = { responseJSON in
            await capturedResponse.set(responseJSON)
        }

        await controller.handleIncomingRPC(
            #"{"jsonrpc":"2.0","method":"bridge.ready","params":{}}"#
        )
        await controller.handleIncomingRPC(
            #"{"jsonrpc":"2.0","id":42,"method":"agent.responseEcho","params":{"text":"hello"}}"#
        )

        let didCaptureResponse = await waitUntil {
            await capturedResponse.get() != nil
        }
        #expect(didCaptureResponse, "Expected response envelope after request dispatch")

        let responseJSON = try #require(await capturedResponse.get())
        let responseData = try #require(responseJSON.data(using: .utf8))
        let response = try JSONDecoder().decode(RPCSuccessEnvelope.self, from: responseData)

        #expect(response.jsonrpc == "2.0")
        #expect(response.id == 42)
        #expect(response.result.echoed == "hello")

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
        let didResolveTitle = await waitForTitle(controller.page, equals: "Bridge")

        // Assert — page loaded from custom scheme with expected URL
        #expect(
            controller.page.url?.absoluteString == "agentstudio://app/index.html",
            "loadApp() should navigate to agentstudio://app/index.html")
        #expect(!(controller.page.isLoading), "Page should finish loading after loadApp()")

        // Assert — BridgeSchemeHandler serves the page (Phase 1 stub returns "Bridge" title)
        #expect(didResolveTitle, "Bridge app page should resolve title before assertion")
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
        let sawProbeMessage = await waitForMessageCount(pageProbe, atLeast: 1)
        #expect(sawProbeMessage, "Expected page-world probe callback")

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
            await Task.yield()
        }
        try #require(!page.isLoading, "Page did not finish loading within \(timeout)")
        await settleAsyncCallbacks(turns: 40)
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

    private func waitForMessageCount(
        _ handler: IntegrationTestMessageHandler,
        atLeast expectedCount: Int,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        await waitUntil(timeout: timeout) {
            handler.receivedMessages.count >= expectedCount
        }
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @escaping () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() {
                return true
            }
            await Task.yield()
        }
        return await condition()
    }

    private func settleAsyncCallbacks(turns: Int = 40) async {
        for _ in 0..<turns {
            await Task.yield()
        }
    }
}

}

// MARK: - Test Message Handler

/// Captures `WKScriptMessage` bodies for assertion in integration tests.
/// Same pattern as the spike tests' `SpikeMessageHandler` but scoped to integration tests.
final class IntegrationTestMessageHandler: NSObject, WKScriptMessageHandler {
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
