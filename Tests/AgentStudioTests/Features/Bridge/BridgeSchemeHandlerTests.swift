import Foundation
import Testing
import WebKit

@testable import AgentStudio

/// Tests for BridgeSchemeHandler static helpers: MIME type resolution and path classification.
///
/// The scheme handler serves bundled React app assets via `agentstudio://app/*` and
/// file contents via `agentstudio://resource/content/<handleId>?generation=<n>`. These tests verify the
/// pure logic layer without requiring a live WebKit instance.
@Suite(.serialized)
final class BridgeSchemeHandlerTests {
    private actor BridgeTelemetryRecorderSpy: BridgePerformanceTraceRecording {
        private var recordedSamples: [BridgeTelemetrySample] = []

        func record(sample: BridgeTelemetrySample, receivedAtUnixNano: UInt64) async {
            recordedSamples.append(sample)
        }

        func recordDrop(
            reason: BridgeTelemetryDropReason,
            droppedCount: Int,
            receivedAtUnixNano: UInt64
        ) async {}

        func samples() -> [BridgeTelemetrySample] {
            recordedSamples
        }
    }

    // MARK: - MIME type resolution

    @Test
    func test_mimeType_html() {
        #expect(BridgeSchemeHandler.mimeType(for: "index.html") == "text/html")
    }

    @Test
    func test_mimeType_htm() {
        #expect(BridgeSchemeHandler.mimeType(for: "page.htm") == "text/html")
    }

    @Test
    func test_mimeType_js() {
        #expect(BridgeSchemeHandler.mimeType(for: "app.js") == "application/javascript")
    }

    @Test
    func test_mimeType_mjs() {
        #expect(BridgeSchemeHandler.mimeType(for: "module.mjs") == "application/javascript")
    }

    @Test
    func test_mimeType_css() {
        #expect(BridgeSchemeHandler.mimeType(for: "styles.css") == "text/css")
    }

    @Test
    func test_mimeType_json() {
        #expect(BridgeSchemeHandler.mimeType(for: "manifest.json") == "application/json")
    }

    @Test
    func test_mimeType_svg() {
        #expect(BridgeSchemeHandler.mimeType(for: "icon.svg") == "image/svg+xml")
    }

    @Test
    func test_mimeType_png() {
        #expect(BridgeSchemeHandler.mimeType(for: "logo.png") == "image/png")
    }

    @Test
    func test_mimeType_woff2() {
        #expect(BridgeSchemeHandler.mimeType(for: "font.woff2") == "font/woff2")
    }

    @Test
    func test_mimeType_wasm() {
        #expect(BridgeSchemeHandler.mimeType(for: "app.wasm") == "application/wasm")
    }

    @Test
    func test_mimeType_unknown_defaults_to_octetStream() {
        #expect(BridgeSchemeHandler.mimeType(for: "data.bin") == "application/octet-stream")
    }

    @Test
    func test_mimeType_noExtension_defaults_to_octetStream() {
        #expect(BridgeSchemeHandler.mimeType(for: "LICENSE") == "application/octet-stream")
    }

    // MARK: - Path classification — app routes

    @Test
    func test_pathType_appRoute_indexHtml() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/index.html")
        #expect(result == .app("index.html"))
    }

    @Test
    func test_pathType_appRoute_nestedAsset() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/assets/main.js")
        #expect(result == .app("assets/main.js"))
    }

    @Test
    func test_appRoute_loadsPackagedBridgeWebIndex() async throws {
        let handler = BridgeSchemeHandler(paneId: UUID())
        let request = URLRequest(url: URL(string: "agentstudio://app/index.html")!)

        var data = Data()
        for try await result in handler.reply(for: request) {
            if case .data(let chunk) = result {
                data.append(chunk)
            }
        }

        let html = try #require(String(data: data, encoding: .utf8))
        #expect(html.contains("<div id=\"root\"></div>"))
        #expect(!html.contains("App: index.html"))
    }

    // MARK: - Path classification — resource routes

    @Test
    func test_pathType_resourceContentRoute() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://resource/content/handle-abc?generation=42")
        #expect(result == .content(handleId: "handle-abc", generation: 42))
    }

    @Test
    func test_pathType_resourceRoute_uuidHandleId() {
        let result = BridgeSchemeHandler.classifyPath(
            "agentstudio://resource/content/550e8400-e29b-41d4-a716-446655440000?generation=7")
        #expect(result == .content(handleId: "550e8400-e29b-41d4-a716-446655440000", generation: 7))
    }

    // MARK: - Path classification — invalid routes

    @Test
    func test_pathType_unknownHost_invalid() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://unknown/path")
        #expect(result == .invalid)
    }

    @Test
    func test_pathType_wrongScheme_invalid() {
        let result = BridgeSchemeHandler.classifyPath("https://app/index.html")
        #expect(result == .invalid)
    }

    @Test
    func test_pathType_emptyAppPath_invalid() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/")
        #expect(result == .invalid)
    }

    @Test
    func test_pathType_resourceMissingFileId_invalid() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://resource/content/?generation=1")
        #expect(result == .invalid)
    }

    @Test
    func test_pathType_resourceWrongSegment_invalid() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://resource/file/abc123?generation=1")
        #expect(result == .invalid)
    }

    @Test
    func test_pathType_resourceMissingGeneration_invalid() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://resource/content/handle-abc")
        #expect(result == .invalid)
    }

    @Test
    func test_pathType_resourceNegativeGeneration_invalid() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://resource/content/handle-abc?generation=-1")
        #expect(result == .invalid)
    }

    @Test
    func test_pathType_resourceOverflowGeneration_invalid() {
        let result = BridgeSchemeHandler.classifyPath(
            "agentstudio://resource/content/handle-abc?generation=99999999999999999999")
        #expect(result == .invalid)
    }

    // MARK: - Path traversal rejection (security)

    @Test
    func test_rejects_path_traversal_dotdot() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/../../../etc/passwd")
        #expect(result == .invalid)
    }

    @Test
    func test_rejects_path_traversal_midPath() {
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/assets/../secret.key")
        #expect(result == .invalid)
    }

    @Test
    func test_rejects_percent_encoded_path_traversal() {
        // %2e%2e is URL-encoded ".." — url.path() decodes it before segment check
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/%2e%2e/etc/passwd")
        #expect(result == .invalid)
    }

    @Test
    func test_allows_benign_encoded_paths() {
        // %2e is a single encoded dot — not traversal, should NOT be rejected
        // e.g. "my%2efile.txt" decodes to "my.file.txt" which is a valid filename
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/my%2efile.txt")
        #expect(result == .app("my.file.txt"))
    }

    @Test
    func test_allows_filenames_containing_double_dots() {
        // "my..config.js" is a valid filename — not a traversal segment
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/my..config.js")
        #expect(result == .app("my..config.js"))
    }

    @Test
    func test_rejects_double_encoded_path_traversal() {
        // %252e%252e → first decode → %2e%2e → second decode → ".."
        // Stable-decode loop catches this.
        let result = BridgeSchemeHandler.classifyPath("agentstudio://app/%252e%252e/etc/passwd")
        #expect(result == .invalid)
    }

    @Test
    func test_appAssetStoreRejectsSymlinkEscapeOutsideAppRoot() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appending(path: "agentstudio-bridge-assets-\(UUID().uuidString)")
        let appRoot = tempRoot.appending(path: "app")
        let outsideRoot = tempRoot.appending(path: "outside")
        try fileManager.createDirectory(at: appRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempRoot)
        }
        let outsideAsset = outsideRoot.appending(path: "secret.txt")
        try Data("secret".utf8).write(to: outsideAsset)
        let symlinkURL = appRoot.appending(path: "secret-link.txt")
        do {
            try fileManager.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideAsset)
        } catch {
            Issue.record("Could not create symlink fixture: \(error)")
            return
        }
        let store = BridgeAppAssetStore(appRootURL: appRoot)

        do {
            _ = try await store.load(relativePath: "secret-link.txt")
            Issue.record("Expected symlink escape to be rejected")
        } catch BridgeSchemeError.invalidRoute {
        } catch {
            Issue.record("Expected invalidRoute, got \(error)")
        }
    }

    @Test
    func test_contentRoute_lazilyLoadsKnownContentFromStore() async throws {
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("hello bridge")
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                handle.handleId: makeContentResult(handle: handle, data: "hello bridge")
            ]
        )
        let contentStore = BridgeContentStore(provider: provider)
        await contentStore.activate(handles: [handle], reviewGeneration: 7)
        let handler = BridgeSchemeHandler(paneId: UUID(), contentStore: contentStore)
        let request = URLRequest(url: URL(string: handle.resourceUrl)!)

        var response: URLResponse?
        var data = Data()
        var eventOrder: [String] = []
        for try await result in handler.reply(for: request) {
            switch result {
            case .response(let emittedResponse):
                response = emittedResponse
                eventOrder.append("response")
            case .data(let chunk):
                data.append(chunk)
                eventOrder.append("data")
            @unknown default:
                Issue.record("Unexpected URL scheme task result")
            }
        }

        #expect(eventOrder == ["response", "data"])
        #expect(response?.mimeType == "text/plain")
        #expect(response?.expectedContentLength == Int64(Data("hello bridge".utf8).count))
        #expect(data == Data("hello bridge".utf8))
        #expect(await provider.recordedContentRequestsCount() == 1)
    }

    @Test
    func test_contentRoute_recordsTraceparentCorrelatedTelemetry() async throws {
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("hello bridge")
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                handle.handleId: makeContentResult(handle: handle, data: "hello bridge")
            ]
        )
        let contentStore = BridgeContentStore(provider: provider)
        let recorder = BridgeTelemetryRecorderSpy()
        await contentStore.activate(handles: [handle], reviewGeneration: 7)
        let handler = BridgeSchemeHandler(
            paneId: UUID(),
            contentStore: contentStore,
            telemetryRecorder: recorder
        )
        var request = URLRequest(url: URL(string: handle.resourceUrl)!)
        request.setValue(
            "00-11111111111111111111111111111111-2222222222222222-01",
            forHTTPHeaderField: "traceparent"
        )

        for try await _ in handler.reply(for: request) {}

        let sample = try #require(await recorder.samples().first)
        #expect(sample.name == "performance.bridge.swift.content_load")
        #expect(sample.scope == .swift)
        #expect(sample.traceContext?.traceId == "11111111111111111111111111111111")
        #expect(sample.stringAttributes["agentstudio.bridge.content.correlation_mode"] == "traceparent")
        #expect(sample.stringAttributes["agentstudio.bridge.cache.result"] == "provider_load")
        #expect(sample.stringAttributes["agentstudio.bridge.transport"] == "content")
        #expect(sample.booleanAttributes["agentstudio.bridge.header_supported"] == true)
        #expect(sample.booleanAttributes["agentstudio.bridge.header_missing"] == false)
    }

    @Test
    func test_contentRoute_recordsSummaryTelemetryWhenTraceparentHeaderMissing() async throws {
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("hello bridge")
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                handle.handleId: makeContentResult(handle: handle, data: "hello bridge")
            ]
        )
        let contentStore = BridgeContentStore(provider: provider)
        let recorder = BridgeTelemetryRecorderSpy()
        await contentStore.activate(handles: [handle], reviewGeneration: 7)
        let handler = BridgeSchemeHandler(
            paneId: UUID(),
            contentStore: contentStore,
            telemetryRecorder: recorder
        )
        let request = URLRequest(url: URL(string: handle.resourceUrl)!)

        for try await _ in handler.reply(for: request) {}

        let sample = try #require(await recorder.samples().first)
        #expect(sample.traceContext == nil)
        #expect(sample.stringAttributes["agentstudio.bridge.content.correlation_mode"] == "summary")
        #expect(sample.booleanAttributes["agentstudio.bridge.header_supported"] == false)
        #expect(sample.booleanAttributes["agentstudio.bridge.header_missing"] == true)
    }

    @Test
    func test_contentRouteUnknownHandleFailsThroughSchemeHandler() async throws {
        let contentStore = BridgeContentStore()
        let recorder = BridgeTelemetryRecorderSpy()
        let handler = BridgeSchemeHandler(
            paneId: UUID(),
            contentStore: contentStore,
            telemetryRecorder: recorder
        )
        let request = URLRequest(url: URL(string: "agentstudio://resource/content/missing?generation=7")!)

        do {
            for try await _ in handler.reply(for: request) {}
            Issue.record("Expected missing content failure")
        } catch let failure as BridgeProviderFailure {
            #expect(failure == .missingContent(handleId: "missing"))
        } catch {
            Issue.record("Expected BridgeProviderFailure, got \(error)")
        }
        let sample = try #require(await recorder.samples().first)
        #expect(sample.stringAttributes["agentstudio.bridge.phase"] == "error")
        #expect(sample.stringAttributes["agentstudio.bridge.cache.result"] == "rejected")
    }

    @Test
    func test_contentRouteCancellationCancelsProviderBackedLoad() async throws {
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("slow")
        )
        let gate = BridgeContentLoadGate()
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                handle.handleId: makeContentResult(handle: handle, data: "slow")
            ],
            contentLoadGate: gate,
            checksCancellationAfterGate: true
        )
        let contentStore = BridgeContentStore(provider: provider)
        await contentStore.activate(handles: [handle], reviewGeneration: 7)
        let handler = BridgeSchemeHandler(paneId: UUID(), contentStore: contentStore)
        let request = URLRequest(url: URL(string: handle.resourceUrl)!)
        let eventRecorder = BridgeSchemeHandlerEventRecorder()
        let stream = handler.reply(for: request)

        let consumerTask = Task {
            do {
                for try await result in stream {
                    switch result {
                    case .response:
                        await eventRecorder.recordEvent()
                    case .data:
                        await eventRecorder.recordEvent()
                    @unknown default:
                        await eventRecorder.recordEvent()
                    }
                }
            } catch is CancellationError {
            } catch {
                await eventRecorder.recordError()
            }
        }
        await gate.waitForStartedLoadCount(1)
        consumerTask.cancel()
        await gate.releaseAll()
        await provider.waitForFinishedContentLoadCount(1)
        _ = await consumerTask.result

        #expect(await provider.recordedObservedCancellationCount() == 1)
        #expect(await eventRecorder.recordedEventCount() == 0)
        #expect(await eventRecorder.recordedErrorCount() == 0)
    }
}

private actor BridgeSchemeHandlerEventRecorder {
    private var eventCount = 0
    private var errorCount = 0

    func recordEvent() {
        eventCount += 1
    }

    func recordError() {
        errorCount += 1
    }

    func recordedEventCount() -> Int {
        eventCount
    }

    func recordedErrorCount() -> Int {
        errorCount
    }
}
