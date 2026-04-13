import Foundation
import Testing
import WebKit

@testable import AgentStudio

/// Round-trip integration tests for the data stream (JS fetch → Swift → JS).
///
/// Verifies: JS `fetch("agentstudio://resource/file/{fileId}")` →
/// `BridgeSchemeHandler` routes to `BridgeFileProvider` → response flows back to JS →
/// page-world test harness captures the result.
extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    final class DataStreamRoundTripTests {

        init() {
            installTestAtomRegistryIfNeeded()
        }

        // MARK: - Test: Fetch resource returns file content

        /// Verify that JS can fetch a file registered in the mock provider
        /// and receive the correct content back.
        @Test
        func test_dataStream_fetchResource_returnsContent() async throws {
            let provider = MockFileProvider()
            provider.register(
                fileId: "test-file-1",
                data: Data("hello world".utf8),
                mimeType: "text/plain"
            )

            let components = RoundTripTestPageBuilder.build(fileProvider: provider)

            try await WebPageTestHarness.withManagedPage(components.page) { page in
                _ = page.load(URL(string: "agentstudio://app/index.html")!)
                let didLoad = await waitUntil { page.url?.absoluteString == "agentstudio://app/index.html" }
                #expect(didLoad)

                let harnessReady = await waitForProbeMessage(components.testProbe, channel: "ready")
                #expect(harnessReady != nil)

                // Act — fetch resource from page world
                _ = try await page.callJavaScript(
                    "window.__testCaptures.fetchResource('test-file-1')"
                )

                // Wait for fetch result
                let fetchResult = await waitForProbeMessage(components.testProbe, channel: "fetch")
                #expect(fetchResult != nil, "Fetch result should arrive in page world")

                if let result = fetchResult {
                    #expect(result["fileId"] as? String == "test-file-1")
                    #expect(result["body"] as? String == "hello world", "Fetched content should match registered data")
                }
            }
        }

        // MARK: - Test: Fetch unknown resource returns error

        /// Verify that fetching an unregistered file ID produces an error response.
        @Test
        func test_dataStream_unknownResource_returnsError() async throws {
            let provider = MockFileProvider()
            // Deliberately NOT registering any files

            let components = RoundTripTestPageBuilder.build(fileProvider: provider)

            try await WebPageTestHarness.withManagedPage(components.page) { page in
                _ = page.load(URL(string: "agentstudio://app/index.html")!)
                let didLoad = await waitUntil { page.url?.absoluteString == "agentstudio://app/index.html" }
                #expect(didLoad)

                let harnessReady = await waitForProbeMessage(components.testProbe, channel: "ready")
                #expect(harnessReady != nil)

                // Act — fetch a file that doesn't exist
                _ = try await page.callJavaScript(
                    "window.__testCaptures.fetchResource('nonexistent-file')"
                )

                // Wait for fetch result — should be an error
                let fetchResult = await waitForProbeMessage(components.testProbe, channel: "fetch")
                #expect(fetchResult != nil, "Fetch error should arrive in page world")

                if let result = fetchResult {
                    #expect(result["fileId"] as? String == "nonexistent-file")
                    // The fetch either fails with ok=false or has an error message
                    let isOk = result["ok"] as? Bool ?? true
                    let hasError = result["error"] as? String != nil
                    #expect(!isOk || hasError, "Failed fetch should indicate error via ok=false or error message")
                }
            }
        }

        // MARK: - Test: MIME type propagates

        /// Verify that the MIME type registered with the file provider
        /// is reflected in the fetch response.
        @Test
        func test_dataStream_mimeType_propagates() async throws {
            let provider = MockFileProvider()
            let jsonContent = #"{"key": "value"}"#
            provider.register(
                fileId: "data-file",
                data: Data(jsonContent.utf8),
                mimeType: "application/json"
            )

            let components = RoundTripTestPageBuilder.build(fileProvider: provider)

            try await WebPageTestHarness.withManagedPage(components.page) { page in
                _ = page.load(URL(string: "agentstudio://app/index.html")!)
                let didLoad = await waitUntil { page.url?.absoluteString == "agentstudio://app/index.html" }
                #expect(didLoad)

                let harnessReady = await waitForProbeMessage(components.testProbe, channel: "ready")
                #expect(harnessReady != nil)

                // Act
                _ = try await page.callJavaScript(
                    "window.__testCaptures.fetchResource('data-file')"
                )

                let fetchResult = await waitForProbeMessage(components.testProbe, channel: "fetch")
                #expect(fetchResult != nil)

                if let result = fetchResult {
                    #expect(result["body"] as? String == jsonContent, "Content should match")
                    // Content-Type header should reflect the registered MIME type
                    let contentType = result["contentType"] as? String ?? ""
                    #expect(contentType.contains("application/json"), "MIME type should propagate")
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
