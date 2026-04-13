import Foundation
import Testing
import WebKit

@testable import AgentStudio

/// Round-trip integration tests for the command stream (JS → Swift).
///
/// Verifies: JS dispatches `__bridge_command` CustomEvent with nonce →
/// bridge world bootstrap validates nonce and relays via `postMessage` →
/// `RPCMessageHandler` → `RPCRouter` dispatches → handler executes.
///
/// Also verifies the response path: handler returns result → `__bridge_response`
/// CustomEvent dispatched → page-world harness captures it.
extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    final class CommandRoundTripTests {

        init() {
            installTestAtomRegistryIfNeeded()
        }

        // MARK: - Test: JS command dispatches to Swift handler

        /// Verify that a command sent from page-world JS arrives at the Swift RPC handler
        /// with the correct method and params.
        @Test
        func test_command_jsDispatchesToSwiftHandler() async throws {
            let components = RoundTripTestPageBuilder.build()

            // Register a test handler that captures received params
            let captured = CaptureBox<String>()
            components.router.register(method: TestEchoMethod.self) { params in
                await captured.set(params.text)
                return nil
            }

            try await WebPageTestHarness.withManagedPage(components.page) { page in
                _ = page.load(URL(string: "agentstudio://app/index.html")!)
                let didLoad = await waitUntil { page.url?.absoluteString == "agentstudio://app/index.html" }
                #expect(didLoad)

                let harnessReady = await waitForProbeMessage(components.testProbe, channel: "ready")
                #expect(harnessReady != nil)

                // Act — execute JS that sends a command from page world
                _ = try await page.callJavaScript(
                    "window.__testCaptures.sendCommand('test.echo', { text: 'hello-from-js' }, 'cmd-001')"
                )

                // Wait for Swift handler to receive the call
                let didCapture = await waitUntil { await captured.get() != nil }
                #expect(didCapture, "Swift handler should receive the command from JS")

                let receivedText = await captured.get()
                #expect(receivedText == "hello-from-js", "Handler should receive correct params")
            }
        }

        // MARK: - Test: Nonce validation rejects invalid nonce

        /// Verify that commands sent with an invalid nonce are rejected by the bootstrap
        /// and never reach the Swift handler.
        @Test
        func test_command_nonceValidation_rejectsInvalidNonce() async throws {
            let components = RoundTripTestPageBuilder.build()

            let callCount = CaptureBox<Int>()
            await callCount.set(0)
            components.router.register(method: TestEchoMethod.self) { _ in
                let current = await callCount.get() ?? 0
                await callCount.set(current + 1)
                return nil
            }

            try await WebPageTestHarness.withManagedPage(components.page) { page in
                _ = page.load(URL(string: "agentstudio://app/index.html")!)
                let didLoad = await waitUntil { page.url?.absoluteString == "agentstudio://app/index.html" }
                #expect(didLoad)

                let harnessReady = await waitForProbeMessage(components.testProbe, channel: "ready")
                #expect(harnessReady != nil)

                // Act — send command with bad nonce
                _ = try await page.callJavaScript(
                    "window.__testCaptures.sendCommandWithBadNonce('test.echo', { text: 'bad' })"
                )

                // Give cooperative yields for any async dispatch to settle
                for _ in 0..<1_000 {
                    await Task.yield()
                }

                // Assert — handler should NOT have been called
                let count = await callCount.get()
                #expect(count == 0, "Handler should not be called for commands with invalid nonce")
            }
        }

        // MARK: - Test: Request/response round-trip

        /// Verify the full request/response cycle: JS sends command with `id` →
        /// Swift handler returns result → response is dispatched as `__bridge_response`
        /// CustomEvent → page-world harness captures it.
        @Test
        func test_command_requestResponse_roundTrip() async throws {
            let components = RoundTripTestPageBuilder.build()
            let bridgeWorld = components.bridgeWorld

            // Register a method that returns a typed result
            components.router.register(method: TestAddMethod.self) { params in
                TestAddMethod.Result(sum: params.a + params.b)
            }

            // Wire the response path (mirrors BridgePaneController.emitRPCResponse):
            // router emits response JSON → callJavaScript to bridge world →
            // __bridge_response CustomEvent → page-world harness captures.
            components.router.onResponse = { [page = components.page] responseJSON in
                try? await page.callJavaScript(
                    """
                    const payload = JSON.parse(json);
                    window.__bridgeInternal.response(payload.id, payload.result, payload.error);
                    """,
                    arguments: ["json": responseJSON],
                    contentWorld: bridgeWorld
                )
            }

            try await WebPageTestHarness.withManagedPage(components.page) { page in
                _ = page.load(URL(string: "agentstudio://app/index.html")!)
                let didLoad = await waitUntil { page.url?.absoluteString == "agentstudio://app/index.html" }
                #expect(didLoad)

                let harnessReady = await waitForProbeMessage(components.testProbe, channel: "ready")
                #expect(harnessReady != nil)

                // Act — send request with id from page world
                _ = try await page.callJavaScript(
                    "window.__testCaptures.sendCommandWithId(99, 'test.add', { a: 3, b: 4 }, 'cmd-add')"
                )

                // Wait for response to arrive in page world
                let response = await waitForProbeMessage(
                    components.testProbe, channel: "response"
                )
                #expect(response != nil, "Response should arrive in page world via __bridge_response")

                // The __bridge_response detail has { id, result, error } from
                // window.__bridgeInternal.response(id, result, error).
                // The result field is the JSON-RPC response "result" object.
                if let result = response?["result"] as? [String: Any] {
                    #expect(result["sum"] as? Int == 7, "Response should contain computed sum")
                }
            }
        }

        // MARK: - Helpers

        private func waitForProbeMessage(
            _ probe: IntegrationTestMessageHandler,
            channel: String,
            afterIndex: Int = -1
        ) async -> [String: Any]? {
            let startIndex = max(afterIndex + 1, 0)

            for _ in 0..<200_000 {
                let messages = probe.receivedMessages
                for i in startIndex..<messages.count {
                    if let jsonString = messages[i] as? String,
                        let data = jsonString.data(using: .utf8),
                        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                        parsed["channel"] as? String == channel
                    {
                        return parsed["data"] as? [String: Any]
                    }
                }
                await Task.yield()
            }
            return nil
        }

        private func waitUntil(
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
    }
}

// MARK: - Test RPC Method Types

private enum TestEchoMethod: RPCMethod {
    struct Params: Decodable, Sendable {
        let text: String
    }
    typealias Result = RPCNoResponse
    static let method = "test.echo"
}

private enum TestAddMethod: RPCMethod {
    struct Params: Decodable, Sendable {
        let a: Int
        let b: Int
    }
    struct Result: Codable, Sendable {
        let sum: Int
    }
    static let method = "test.add"
}

// MARK: - CaptureBox

/// Actor-isolated capture box for safely recording values from async handlers.
actor CaptureBox<T: Sendable> {
    private var value: T?

    func set(_ newValue: T) {
        value = newValue
    }

    func get() -> T? {
        value
    }
}
