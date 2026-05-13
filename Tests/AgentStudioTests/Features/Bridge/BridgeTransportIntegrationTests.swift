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
///
/// Unlike the spike tests which exercise raw WebKit APIs, these tests exercise
/// the fully-assembled BridgePaneController and its real dependencies.
extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    final class BridgeTransportIntegrationTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        // MARK: - Test 1: Bridge.ready handshake gating

        /// Verify that `isBridgeReady` starts false, becomes true after `handleBridgeReady()`,
        /// and remains true on repeated calls (idempotent gating per §4.5 line 246).
        @Test
        func test_bridgeReady_gatesAndIsIdempotent() async {
            // Arrange — create a controller with default bridge pane state
            let paneId = UUIDv7.generate()
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
            let paneId = UUIDv7.generate()
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
            let paneId = UUIDv7.generate()
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

            let paneId = UUIDv7.generate()
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
            let paneId = UUIDv7.generate()
            let state = BridgePaneState(panelKind: .diffViewer, source: nil)
            let controller = BridgePaneController(paneId: paneId, state: state)
            defer { controller.teardown() }

            try await WebPageTestHarness.withManagedPage(controller.page) { page in
                // Act — load the bundled React app URL
                controller.loadApp()
                let didNavigateToAppURL = await waitUntil {
                    page.url?.absoluteString == "agentstudio://app/index.html"
                }
                try await waitForPageLoad(page)
                let didResolveTitle = await waitForTitle(page, equals: "Bridge")

                // Assert — page loaded from custom scheme with expected URL
                #expect(didNavigateToAppURL, "loadApp() should navigate to agentstudio://app/index.html")

                // Assert — BridgeSchemeHandler serves the page (Phase 1 stub returns "Bridge" title)
                #expect(didResolveTitle, "Bridge app page should resolve title before assertion")
                #expect(
                    page.title == "Bridge",
                    "BridgeSchemeHandler should serve HTML with <title>Bridge</title> for app routes")
            }
        }

        // MARK: - Helpers

        private func waitForTitle(
            _ page: WebPage,
            equals expectedTitle: String,
            timeout: Duration = .seconds(2)
        ) async -> Bool {
            for _ in 0..<20_000 {
                if page.title == expectedTitle {
                    return true
                }
                await Task.yield()
            }
            return page.title == expectedTitle
        }

        private func waitForPageLoad(_ page: WebPage, timeout: Duration = .seconds(5)) async throws {
            for _ in 0..<50_000 {
                if !page.isLoading { break }
                await Task.yield()
            }
            try #require(!page.isLoading, "Page did not finish loading within \(timeout)")
            await settleAsyncCallbacks(turns: 40)
        }

        private func waitUntil(
            timeout: Duration = .seconds(2),
            _ condition: @escaping () async -> Bool
        ) async -> Bool {
            for _ in 0..<200_000 {
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
