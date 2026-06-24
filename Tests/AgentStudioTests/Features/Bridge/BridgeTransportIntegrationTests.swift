import Foundation
import Testing
import WebKit

@testable import AgentStudio

private actor TraceparentHeaderCapture {
    private var didRecordResourceRequest = false
    private var traceparentHeader: String?

    func recordResourceRequest(_ request: URLRequest) {
        didRecordResourceRequest = true
        traceparentHeader = request.value(forHTTPHeaderField: "traceparent")
    }

    func didRecord() -> Bool {
        didRecordResourceRequest
    }

    func traceparent() -> String? {
        traceparentHeader
    }
}

private struct TraceparentCaptureSchemeHandler: URLSchemeHandler {
    let capture: TraceparentHeaderCapture

    func reply(for request: URLRequest) -> some AsyncSequence<URLSchemeTaskResult, any Error> {
        AsyncThrowingStream<URLSchemeTaskResult, any Error> { continuation in
            guard let url = request.url else {
                continuation.finish(throwing: BridgeSchemeError.invalidRequest("Missing URL"))
                return
            }

            if url.host() == "resource" {
                Task {
                    await capture.recordResourceRequest(request)
                }
                let data = Data("content".utf8)
                continuation.yield(
                    .response(
                        BridgeSchemeHandler.response(
                            url: url,
                            mimeType: "text/plain",
                            expectedContentLength: data.count
                        )))
                continuation.yield(.data(data))
                continuation.finish()
                return
            }

            let html = """
                <html>
                  <head><title>Traceparent Fetch</title></head>
                  <body>
                    <script>
                      fetch('agentstudio://resource/review/content/handle?generation=1', {
                        headers: {
                          traceparent: '00-11111111111111111111111111111111-2222222222222222-01'
                        }
                      }).then(function() {
                        document.title = 'Traceparent Fetch Done';
                      }).catch(function() {
                        document.title = 'Traceparent Fetch Failed';
                      });
                    </script>
                  </body>
                </html>
                """
            let data = Data(html.utf8)
            continuation.yield(
                .response(
                    BridgeSchemeHandler.response(
                        url: url,
                        mimeType: "text/html",
                        expectedContentLength: data.count
                    )))
            continuation.yield(.data(data))
            continuation.finish()
        }
    }
}

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

            // Arrange — enable push plans without loading a page.
            let controller = BridgePaneController(
                paneId: paneId,
                state: state,
                pushEnvelopeSink: { _, _, _ in
                    throw NSError(domain: "BridgeTransportIntegrationTests", code: 101)
                }
            )
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
                let didResolveTitle = await waitForTitle(page, equals: "AgentStudio Bridge")
                let didCompleteBridgeReadyHandshake = await waitUntil {
                    controller.isBridgeReady
                }

                // Assert — page loaded from custom scheme with expected URL
                #expect(didNavigateToAppURL, "loadApp() should navigate to agentstudio://app/index.html")

                // Assert — BridgeSchemeHandler serves the packaged Bridge app HTML.
                #expect(didResolveTitle, "Bridge app page should resolve title before assertion")
                #expect(
                    page.title == "AgentStudio Bridge",
                    "BridgeSchemeHandler should serve packaged Bridge app HTML for app routes")

                // Assert — the packaged module script executes and sends the bridge.ready handshake.
                #expect(
                    didCompleteBridgeReadyHandshake,
                    "Bridge app JavaScript should boot React and send bridge.ready after index.html loads")
                _ = try await page.callJavaScript(
                    """
                    document.title = document.body.innerText.includes('Waiting for review package')
                      ? 'AgentStudio Bridge Visible'
                      : 'AgentStudio Bridge Missing Shell'
                    """
                )
                let didRenderEmptyShell = await waitForTitle(page, equals: "AgentStudio Bridge Visible")
                #expect(
                    didRenderEmptyShell,
                    "Bridge app JavaScript should render the visible empty review shell after boot")
            }
        }

        @Test
        func test_pushPackageMetadata_rendersReviewViewerShell() async throws {
            let paneId = UUIDv7.generate()
            let state = BridgePaneState(panelKind: .diffViewer, source: nil)
            let controller = BridgePaneController(paneId: paneId, state: state)
            defer { controller.teardown() }

            let baseHandle = makeBridgeContentHandle(
                itemId: "item-shell",
                role: .base,
                endpointId: "shell-base",
                reviewGeneration: BridgeReviewGeneration(7),
                contentHash: bridgeSHA256ContentHash("base content"),
                sizeBytes: 12
            )
            let headHandle = makeBridgeContentHandle(
                itemId: "item-shell",
                role: .head,
                endpointId: "shell-head",
                reviewGeneration: BridgeReviewGeneration(7),
                contentHash: bridgeSHA256ContentHash("head content"),
                sizeBytes: 12
            )
            let package = makeTransportContentPackage(
                baseHandle: baseHandle,
                headHandle: headHandle,
                worktreeId: paneId
            )
            try await controller.reviewContentStore.register(
                makeContentResult(handle: baseHandle, data: "base content"))
            try await controller.reviewContentStore.register(
                makeContentResult(handle: headHandle, data: "head content"))
            try await registerContentHandleLeases(
                controller: controller,
                paneId: paneId,
                handles: [baseHandle, headHandle]
            )
            let snapshotFrame = try makeReviewSnapshotProtocolFrame(
                package: package,
                paneId: paneId
            )
            let payload = try JSONEncoder().encode(
                DiffPackageMetadataSlice(package: package, protocolFrame: snapshotFrame))

            try await WebPageTestHarness.withManagedPage(controller.page) { page in
                controller.loadApp()
                try await waitForPageLoad(page)
                let didCompleteBridgeReadyHandshake = await waitUntil {
                    controller.isBridgeReady
                }
                #expect(
                    didCompleteBridgeReadyHandshake,
                    "Bridge app JavaScript should send bridge.ready before package pushes")
                let didRenderEmptyShell = await waitUntil(timeout: .seconds(1)) {
                    await pageContainsEmptyReviewShell(page)
                }
                #expect(didRenderEmptyShell, "Bridge app should render its empty shell before package pushes")
                try await installPageDiagnosticsProbe(page)

                await controller.pushJSON(
                    metadata: BridgePushEnvelopeMetadata(
                        store: .diff,
                        op: .replace,
                        level: .cold,
                        slice: .diffPackageMetadata,
                        revision: 1,
                        epoch: package.reviewGeneration.rawValue
                    ),
                    json: payload
                )

                let didRenderReviewShell = await waitUntil(timeout: .seconds(1)) {
                    (try? await controller.renderStateForIPC().summary.hasReviewShell) == true
                }
                let pageState = await describeBridgePageState(page)
                #expect(
                    didRenderReviewShell,
                    "Pushed package metadata should render the review viewer shell: \(pageState)")
                let renderState = try await controller.renderStateForIPC()
                #expect(renderState.summary.hasReviewShell)
                #expect(!(renderState.summary.hasEmptyShell))
                #expect(renderState.summary.sidebarPosition == "right")
                #expect(renderState.diagnostics.evaluateSucceeded)
                #expect(renderState.diagnostics.pageErrorCount == 0)
                #expect(renderState.diagnostics.pageErrorKinds.isEmpty)
            }
        }

        @Test
        func test_pushJSON_concurrentBurstDeliversOrderedPageEvents() async throws {
            let paneId = UUIDv7.generate()
            let state = BridgePaneState(panelKind: .diffViewer, source: nil)
            let controller = BridgePaneController(paneId: paneId, state: state)
            defer { controller.teardown() }

            try await WebPageTestHarness.withManagedPage(controller.page) { page in
                let burstToken = UUID().uuidString
                controller.loadApp()
                try await waitForPageLoad(page)
                let didCompleteBridgeReadyHandshake = await waitUntil {
                    controller.isBridgeReady
                }
                #expect(
                    didCompleteBridgeReadyHandshake,
                    "Bridge app JavaScript should send bridge.ready before burst pushes")
                try await installPageDiagnosticsProbe(page)

                let pushTasks = (1...8).map { revision in
                    Task { @MainActor in
                        await controller.pushJSON(
                            metadata: BridgePushEnvelopeMetadata(
                                store: .diff,
                                op: .replace,
                                level: .hot,
                                slice: .diffStatus,
                                revision: revision,
                                epoch: 1
                            ),
                            json: Data(
                                #"{"status":"ready","error":null,"epoch":\#(revision),"burstToken":"\#(burstToken)"}"#
                                    .utf8
                            )
                        )
                    }
                }
                for pushTask in pushTasks {
                    await pushTask.value
                }

                let didObserveBurst = await waitUntil(timeout: .seconds(1)) {
                    await bridgePushProbeRevisionOrder(page, burstToken: burstToken).count == 8
                }
                let observedRevisions = await bridgePushProbeRevisionOrder(page, burstToken: burstToken)
                let pageState = await describeBridgePageState(page)

                #expect(didObserveBurst, "Expected all burst push events in page probe: \(pageState)")
                #expect(observedRevisions == Array(1...8), "Expected ordered burst delivery: \(pageState)")
            }
        }

        @Test
        func test_handleDiffCommandWithSmokeProvider_rendersReviewViewerShell() async throws {
            let paneId = UUIDv7.generate()
            let state = BridgePaneState(panelKind: .diffViewer, source: nil)
            let controller = BridgePaneController(
                paneId: paneId,
                state: state,
                reviewSourceProvider: BridgeObservabilitySmokeReviewSourceProvider()
            )
            defer { controller.teardown() }

            try await WebPageTestHarness.withManagedPage(controller.page) { page in
                controller.loadApp()
                try await waitForPageLoad(page)
                let didCompleteBridgeReadyHandshake = await waitUntil {
                    controller.isBridgeReady
                }
                #expect(
                    didCompleteBridgeReadyHandshake,
                    "Bridge app JavaScript should send bridge.ready before command-driven package load")
                try await installPageDiagnosticsProbe(page)

                let commandResult = await controller.handleDiffCommand(
                    .loadDiff(
                        DiffArtifact(
                            diffId: BridgeObservabilitySmokeReviewSourceProvider.diffId,
                            worktreeId: BridgeObservabilitySmokeReviewSourceProvider.worktreeId,
                            patchData: Data()
                        )
                    ),
                    commandId: UUIDv7.generate(),
                    correlationId: nil
                )

                guard case .success = commandResult else {
                    Issue.record("Expected smoke provider diff command to succeed")
                    return
                }

                let didRenderReviewShell = await waitUntil(timeout: .seconds(1)) {
                    (try? await controller.renderStateForIPC().summary.hasReviewShell) == true
                }
                let renderState = try await controller.renderStateForIPC()
                let pageState = await describeBridgePageState(page)
                #expect(
                    didRenderReviewShell,
                    "Command-driven smoke package should render review shell: \(pageState)")
                #expect(renderState.summary.hasReviewShell)
                #expect(!(renderState.summary.hasEmptyShell))
                #expect(renderState.diagnostics.evaluateSucceeded)
                #expect(renderState.diagnostics.pageErrorCount == 0)
            }
        }

        @Test
        func test_contentFetch_traceparentHeaderReachesCustomSchemeHandler() async throws {
            guard isTraceparentFetchProofEnabled() else { return }
            let capture = TraceparentHeaderCapture()
            var config = WebPageTestHarness.makeConfiguration()
            config.urlSchemeHandlers[URLScheme("agentstudio")!] = TraceparentCaptureSchemeHandler(capture: capture)
            let page = WebPage(
                configuration: config,
                navigationDecider: BridgeNavigationDecider(),
                dialogPresenter: WebviewDialogHandler()
            )

            try await WebPageTestHarness.withManagedPage(page) { page in
                _ = page.load(URL(string: "agentstudio://app/traceparent.html")!)
                let didRecordResourceRequest = await waitUntil {
                    await capture.didRecord()
                }
                let didResolveFetch = await waitForTitle(page, equals: "Traceparent Fetch Done")

                #expect(didRecordResourceRequest, "Expected fetch to reach the custom resource scheme handler")
                #expect(didResolveFetch, "Expected page-side fetch to resolve for custom resource scheme")
                #expect(
                    await capture.traceparent()
                        == "00-11111111111111111111111111111111-2222222222222222-01",
                    "WebKit should preserve traceparent on agentstudio://resource/review/content fetches")
            }
        }

        @Test
        func test_contentFetch_realDiffHandlesResolveAndDoNotRejectThroughReviewViewer() async throws {
            let paneId = UUIDv7.generate()
            let state = BridgePaneState(panelKind: .diffViewer, source: nil)
            let controller = BridgePaneController(paneId: paneId, state: state)
            defer { controller.teardown() }

            let (baseHandle, headHandle) = makeRealDiffContentHandles()
            let package = makeTransportContentPackage(
                baseHandle: baseHandle,
                headHandle: headHandle,
                worktreeId: paneId
            )
            try await controller.reviewContentStore.register(
                makeContentResult(handle: baseHandle, data: "base content"))
            try await controller.reviewContentStore.register(
                makeContentResult(handle: headHandle, data: "head content"))
            try await registerContentHandleLeases(
                controller: controller,
                paneId: paneId,
                handles: [baseHandle, headHandle]
            )
            let snapshotFrame = try makeReviewSnapshotProtocolFrame(
                package: package,
                paneId: paneId
            )
            let payload = try JSONEncoder().encode(
                DiffPackageMetadataSlice(package: package, protocolFrame: snapshotFrame))
            let baseResourceURLJSON = try #require(
                String(data: JSONEncoder().encode(baseHandle.resourceUrl), encoding: .utf8))
            let headResourceURLJSON = try #require(
                String(data: JSONEncoder().encode(headHandle.resourceUrl), encoding: .utf8))

            try await WebPageTestHarness.withManagedPage(controller.page) { page in
                controller.loadApp()
                try await waitForPageLoad(page)
                let didCompleteBridgeReadyHandshake = await waitUntil {
                    controller.isBridgeReady
                }
                #expect(
                    didCompleteBridgeReadyHandshake,
                    "Bridge app JavaScript should send bridge.ready before package pushes")
                try await installPageDiagnosticsProbe(page)

                _ = try await page.callJavaScript(
                    """
                    window.__bridgeConcurrentContentFetchResult = null;
                    Promise.all([
                      fetch(\(baseResourceURLJSON)).then(async function(response) {
                        return { ok: response.ok, status: response.status, text: await response.text() };
                      }),
                      fetch(\(headResourceURLJSON)).then(async function(response) {
                        return { ok: response.ok, status: response.status, text: await response.text() };
                      })
                    ]).then(function(results) {
                      window.__bridgeConcurrentContentFetchResult = { ok: true, results: results };
                      document.title = 'Concurrent Content Fetch Done';
                    }).catch(function(error) {
                      window.__bridgeConcurrentContentFetchResult = {
                        ok: false,
                        message: String(error && error.message ? error.message : error)
                      };
                      document.title = 'Concurrent Content Fetch Failed';
                    });
                    """
                )
                let didResolveFetch = await waitForTitle(page, equals: "Concurrent Content Fetch Done")
                let result = try await page.callJavaScript(
                    """
                    return JSON.stringify(window.__bridgeConcurrentContentFetchResult)
                    """
                )
                let resultDescription = String(describing: result)

                #expect(
                    didResolveFetch,
                    "Expected concurrent real Bridge content fetches to resolve: \(resultDescription)")
                #expect(resultDescription.contains(#""text":"base content""#), "Expected base content body")
                #expect(resultDescription.contains(#""text":"head content""#), "Expected head content body")

                await controller.pushJSON(
                    metadata: BridgePushEnvelopeMetadata(
                        store: .diff,
                        op: .replace,
                        level: .cold,
                        slice: .diffPackageMetadata,
                        revision: 1,
                        epoch: package.reviewGeneration.rawValue
                    ),
                    json: payload
                )

                let didKeepReviewShellStable = await waitUntil(timeout: .seconds(1)) {
                    await pageContainsReviewShell(page)
                }
                let pageState = await describeBridgePageState(page)
                let errorProbe = await pageErrorProbeDescription(page)

                #expect(
                    didKeepReviewShellStable,
                    "Expected ReviewViewer shell to remain stable during real diff hydration: \(pageState)")
                #expect(errorProbe == "[]", "Expected no page errors during real diff hydration: \(errorProbe)")
            }
        }

    }
}

@MainActor
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

@MainActor
private func waitForPageLoad(_ page: WebPage, timeout: Duration = .seconds(2)) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if !page.isLoading { break }
        await Task.yield()
    }
    try #require(!page.isLoading, "Page did not finish loading within \(timeout)")
    await settleAsyncCallbacks(turns: 40)
}

@MainActor
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

@MainActor
private func settleAsyncCallbacks(turns: Int = 40) async {
    for _ in 0..<turns {
        await Task.yield()
    }
}

@MainActor
private func isTraceparentFetchProofEnabled() -> Bool {
    ProcessInfo.processInfo.environment["AGENT_STUDIO_WEBKIT_TRACEPARENT_FETCH_PROOF"] == "on"
}

@MainActor
private func decodeBridgeReviewPackageFixture() throws -> BridgeReviewPackage {
    let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
    let fixtureURL = projectRoot.appending(
        path: "Tests/BridgeContractFixtures/valid/bridge-review-package.json"
    )
    let data = try Data(contentsOf: fixtureURL)
    return try JSONDecoder().decode(BridgeReviewPackage.self, from: data)
}

@MainActor
private func makeTransportContentPackage(
    baseHandle: BridgeContentHandle?,
    headHandle: BridgeContentHandle,
    worktreeId: UUID
) -> BridgeReviewPackage {
    let baseEndpoint = makeTransportSourceEndpoint(
        endpointId: "transport-base",
        kind: .gitRef,
        worktreeId: worktreeId,
        label: "Base"
    )
    let headEndpoint = makeTransportSourceEndpoint(
        endpointId: headHandle.endpointId,
        kind: .workingTree,
        worktreeId: worktreeId,
        label: "Head"
    )
    let item = makeBridgeReviewItemDescriptor(
        itemId: headHandle.itemId,
        path: "Sources/RealContent.swift",
        fileClass: .source,
        contentRoles: BridgeReviewItemDescriptor.ContentRoles(
            base: baseHandle,
            head: headHandle
        )
    )
    return BridgeReviewPackage(
        packageId: "package-real-content",
        schemaVersion: 1,
        reviewGeneration: headHandle.reviewGeneration,
        revision: 0,
        query: BridgeReviewQuery(
            queryId: "query-real-content",
            queryKind: .compare,
            repoId: worktreeId,
            worktreeId: worktreeId,
            baseEndpointId: baseEndpoint.endpointId,
            headEndpointId: headEndpoint.endpointId,
            comparisonSemantics: .workingTreeDelta,
            pathScope: [],
            fileTarget: nil,
            viewFilter: BridgeViewFilter(),
            grouping: BridgeChangeGrouping(kind: .flat),
            provenanceFilter: BridgeProvenanceFilter()
        ),
        baseEndpoint: baseEndpoint,
        headEndpoint: headEndpoint,
        orderedItemIds: [item.itemId],
        itemsById: [item.itemId: item],
        groups: [],
        summary: BridgeReviewPackageSummary(
            filesChanged: 1,
            additions: 1,
            deletions: 0,
            visibleFileCount: 1,
            hiddenFileCount: 0
        ),
        filterState: BridgeViewFilter(),
        generatedAtUnixMilliseconds: 200
    )
}

@MainActor
private func makeTransportSourceEndpoint(
    endpointId: String,
    kind: BridgeSourceEndpoint.Kind,
    worktreeId: UUID,
    label: String
) -> BridgeSourceEndpoint {
    BridgeSourceEndpoint(
        endpointId: endpointId,
        kind: kind,
        repoId: worktreeId,
        worktreeId: worktreeId,
        label: label,
        createdAtUnixMilliseconds: 100,
        contentSetHash: nil,
        providerIdentity: "transport-test"
    )
}

@MainActor
private func makeReviewSnapshotProtocolFrame(
    package: BridgeReviewPackage,
    paneId: UUID
) throws -> BridgeReviewSnapshotFrame {
    try BridgeReviewProtocolFrameBuilder.snapshot(
        request: BridgeReviewProtocolSnapshotBuildRequest(
            paneId: paneId.uuidString,
            sourceIdentity: package.query.queryId,
            streamId: "review:\(paneId.uuidString)",
            sequence: package.revision,
            package: package,
            changesetCluster: package.changesetCluster
        )
    )
}

@MainActor
private func pageContainsEmptyReviewShell(_ page: WebPage) async -> Bool {
    do {
        let result = try await page.callJavaScript(
            """
            return document.querySelector('[data-testid="bridge-review-empty-shell"]') !== null &&
              document.body.innerText.includes('Waiting for review package')
            """
        )
        return (result as? Bool) == true
    } catch {
        return false
    }
}

@MainActor
private func pageContainsReviewShell(_ page: WebPage) async -> Bool {
    do {
        let result = try await page.callJavaScript(
            """
            return document.querySelector('[data-testid="review-viewer-shell"]') !== null
            """
        )
        return (result as? Bool) == true
    } catch {
        return false
    }
}

@MainActor
private func pageErrorProbeDescription(_ page: WebPage) async -> String {
    do {
        let result = try await page.callJavaScript(
            """
            return JSON.stringify(window.__bridgeErrorProbe ?? [])
            """
        )
        return (result as? String) ?? String(describing: result)
    } catch {
        return String(describing: error)
    }
}

@MainActor
private func installPageDiagnosticsProbe(_ page: WebPage) async throws {
    _ = try await page.callJavaScript(
        """
        window.__bridgePushProbe = [];
        window.__bridgeErrorProbe = [];
        window.addEventListener('error', function(event) {
          window.__bridgeErrorProbe.push({
            kind: 'error',
            message: String(event.message),
            filename: String(event.filename || ''),
            line: event.lineno,
            column: event.colno,
            stack: event.error?.stack ? String(event.error.stack).slice(0, 800) : null
          });
        });
        window.addEventListener('unhandledrejection', function(event) {
          window.__bridgeErrorProbe.push({
            kind: 'unhandledrejection',
            message: String(event.reason?.message || event.reason),
            stack: event.reason?.stack ? String(event.reason.stack).slice(0, 800) : null
          });
        });
        document.addEventListener('__bridge_push_json', function(event) {
          var revision = null;
          var burstToken = null;
          try {
            var parsedEnvelope = JSON.parse(event.detail?.json || '{}');
            revision = parsedEnvelope.__revision ?? null;
            burstToken = parsedEnvelope.payload?.burstToken ?? null;
          } catch (error) {
            revision = null;
            burstToken = null;
          }
          window.__bridgePushProbe.push({
            hasDetail: Boolean(event.detail),
            hasJson: typeof event.detail?.json === 'string',
            jsonLength: typeof event.detail?.json === 'string' ? event.detail.json.length : -1,
            nonceLength: typeof event.detail?.nonce === 'string' ? event.detail.nonce.length : -1,
            revision: revision,
            burstToken: burstToken
          });
        });
        """
    )
}

@MainActor
private func bridgePushProbeRevisionOrder(_ page: WebPage, burstToken: String) async -> [Int] {
    let burstTokenJSON = (try? String(data: JSONEncoder().encode(burstToken), encoding: .utf8)) ?? #""""#
    do {
        let result = try await page.callJavaScript(
            """
            return JSON.stringify((window.__bridgePushProbe ?? []).filter(function(entry) {
              return entry.burstToken === \(burstTokenJSON);
            }).map(function(entry) {
              return entry.revision;
            }).filter(function(revision) {
              return typeof revision === 'number';
            }))
            """
        )
        guard let json = result as? String,
            let data = json.data(using: .utf8)
        else {
            return []
        }
        return (try? JSONDecoder().decode([Int].self, from: data)) ?? []
    } catch {
        return []
    }
}

@MainActor
private func describeBridgePageState(_ page: WebPage) async -> String {
    do {
        let result = try await page.callJavaScript(
            """
            return JSON.stringify({
              title: document.title,
              hasAppRoot: document.querySelector('[data-testid="bridge-app-root"]') !== null,
              hasEmptyShell: document.querySelector('[data-testid="bridge-review-empty-shell"]') !== null,
              hasReviewShell: document.querySelector('[data-testid="review-viewer-shell"]') !== null,
              bridgeInternalType: typeof window.__bridgeInternal,
              pushProbe: window.__bridgePushProbe ?? [],
              errorProbe: window.__bridgeErrorProbe ?? [],
              text: document.body.innerText.slice(0, 240)
            })
            """
        )
        return (result as? String) ?? String(describing: result)
    } catch {
        return "page-state-error=\(String(describing: error))"
    }
}

@MainActor
private func registerContentHandleLeases(
    controller: BridgePaneController,
    paneId: UUID,
    handles: [BridgeContentHandle]
) async throws {
    for handle in handles {
        let resource = try #require(
            BridgeTransportResourceURL.parse(
                handle.resourceUrl,
                allowedResourceKindsByProtocol: ["review": Set(["content"])]
            ))
        await controller.resourceLeaseRegistry.register(
            resource,
            paneId: paneId,
            descriptorId: resource.opaqueId,
            maxBytes: handle.sizeBytes,
            expectedRevocationRevision: 0
        )
    }
}

@MainActor
private func makeRealDiffContentHandles() -> (
    base: BridgeContentHandle,
    head: BridgeContentHandle
) {
    (
        base: makeBridgeContentHandle(
            itemId: "item-real-diff",
            role: .base,
            endpointId: "transport-base",
            reviewGeneration: BridgeReviewGeneration(7),
            contentHash: bridgeSHA256ContentHash("base content"),
            sizeBytes: 12
        ),
        head: makeBridgeContentHandle(
            itemId: "item-real-diff",
            role: .head,
            endpointId: "transport-head",
            reviewGeneration: BridgeReviewGeneration(7),
            contentHash: bridgeSHA256ContentHash("head content"),
            sizeBytes: 12
        )
    )
}
