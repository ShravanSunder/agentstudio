import Foundation
import WebKit

/// URL scheme handler for `agentstudio://` custom scheme.
///
/// Routes:
/// - `agentstudio://app/*` — bundled React app assets (HTML, JS, CSS)
/// - `agentstudio://resource/<protocol>/<kind>/<opaqueId>?generation=<n>` — leased resources on demand
/// - product command, metadata-stream, and content POSTs routed through the pane session
struct BridgeSchemeHandler: URLSchemeHandler, Sendable {
    private struct BridgeSchemeContentEmissionRequest {
        let handleId: String
        let generation: BridgeReviewGeneration
        let url: URL
        let request: URLRequest
        let readMethod: BridgeSchemeReadMethod
        let leasedResource: BridgeTransportResourceURL
        let interest: BridgeContentDemandInterest
    }

    let paneId: UUID
    let contentStore: BridgeContentStore
    let appAssetStore: BridgeAppAssetStore
    let resourceLeaseRegistry: BridgeTransportResourceLeaseRegistry
    let allowedResourceKindsByProtocol: [String: Set<String>]
    let telemetryRecorder: (any BridgePerformanceTraceRecording)?
    let telemetrySessionOwner: BridgePaneTelemetrySessionOwner?
    let productSessionRouter: BridgeProductSchemeSessionRouter?
    let beforeContentEmission: (@Sendable () async -> Void)?
    let contentDemandAdmission: BridgeContentDemandAdmission
    private static let resourceChunkByteCount = 64 * 1024
    private static let invalidRouteReason = "invalid-route"

    init(
        paneId: UUID,
        contentStore: BridgeContentStore = BridgeContentStore(),
        appAssetStore: BridgeAppAssetStore = BridgeAppAssetStore(),
        resourceLeaseRegistry: BridgeTransportResourceLeaseRegistry = BridgeTransportResourceLeaseRegistry(),
        allowedResourceKindsByProtocol: [String: Set<String>] =
            BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds,
        telemetryRecorder: (any BridgePerformanceTraceRecording)? = nil,
        telemetrySessionOwner: BridgePaneTelemetrySessionOwner? = nil,
        productSessionRouter: BridgeProductSchemeSessionRouter? = nil,
        beforeContentEmission: (@Sendable () async -> Void)? = nil,
        contentDemandAdmission: BridgeContentDemandAdmission = BridgeContentDemandAdmission()
    ) {
        self.paneId = paneId
        self.contentStore = contentStore
        self.appAssetStore = appAssetStore
        self.resourceLeaseRegistry = resourceLeaseRegistry
        self.allowedResourceKindsByProtocol = allowedResourceKindsByProtocol
        self.telemetryRecorder = telemetryRecorder
        self.telemetrySessionOwner = telemetrySessionOwner
        self.productSessionRouter = productSessionRouter
        self.beforeContentEmission = beforeContentEmission
        self.contentDemandAdmission = contentDemandAdmission
    }

    // MARK: - URLSchemeHandler

    func reply(for request: URLRequest) -> some AsyncSequence<URLSchemeTaskResult, any Error> {
        AsyncThrowingStream<URLSchemeTaskResult, any Error> { continuation in
            routeReply(for: request, continuation: continuation)
        }
    }

    private func routeReply(
        for request: URLRequest,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) {
        guard let url = request.url else {
            continuation.finish(throwing: BridgeSchemeError.invalidRequest("Missing URL"))
            return
        }
        guard let readMethod = Self.readMethod(from: request.httpMethod) else {
            continuation.finish(throwing: BridgeSchemeError.invalidRequest("Unsupported method"))
            return
        }

        let classification = Self.classifyPath(
            url.absoluteString,
            allowedResourceKindsByProtocol: allowedResourceKindsByProtocol
        )
        if readMethod == .options, classification != .product {
            emitOptionsResponse(url: url, classification: classification, continuation: continuation)
            return
        }
        guard readMethod != .post || classification.supportsPostRequests else {
            continuation.finish(throwing: BridgeSchemeError.invalidRequest("Unsupported method"))
            return
        }
        switch classification {
        case .app(let relativePath):
            startAppAssetReplyTask(
                relativePath: relativePath,
                url: url,
                readMethod: readMethod,
                continuation: continuation
            )
        case .leasedContent(let resource):
            startLeasedResourceReplyTask(
                resource: resource,
                url: url,
                request: request,
                readMethod: readMethod,
                continuation: continuation
            )
        case .telemetryBatch:
            startTelemetryBatchReplyTask(
                url: url,
                request: request,
                readMethod: readMethod,
                continuation: continuation
            )
        case .product:
            startProductReplyTask(request: request, continuation: continuation)
        case .invalid:
            continuation.finish(throwing: BridgeSchemeError.invalidRoute(Self.invalidRouteReason))
        }
    }

    private func emitOptionsResponse(
        url: URL,
        classification: PathType,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) {
        guard classification != .invalid else {
            continuation.finish(throwing: BridgeSchemeError.invalidRoute(Self.invalidRouteReason))
            return
        }
        continuation.yield(
            .response(
                Self.response(
                    url: url,
                    mimeType: "text/plain",
                    expectedContentLength: 0,
                    allowedMethods: Self.allowedMethods(for: classification)
                )))
        continuation.finish()
    }

    private func startAppAssetReplyTask(
        relativePath: String,
        url: URL,
        readMethod: BridgeSchemeReadMethod,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) {
        let task = Task {
            do {
                let asset = try await appAssetStore.load(relativePath: relativePath)
                try Task.checkCancellation()
                continuation.yield(
                    .response(
                        Self.response(
                            url: url,
                            mimeType: asset.mimeType,
                            expectedContentLength: asset.data.count
                        )))
                if readMethod == .get {
                    try Task.checkCancellation()
                    continuation.yield(.data(asset.data))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
    }

    private func startLeasedResourceReplyTask(
        resource: BridgeTransportResourceURL,
        url: URL,
        request: URLRequest,
        readMethod: BridgeSchemeReadMethod,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) {
        let task = Task {
            await routeLeasedResourceReply(
                resource: resource,
                url: url,
                request: request,
                readMethod: readMethod,
                continuation: continuation
            )
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
    }

    private func routeLeasedResourceReply(
        resource: BridgeTransportResourceURL,
        url: URL,
        request: URLRequest,
        readMethod: BridgeSchemeReadMethod,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) async {
        if resource.protocolId == "review",
            resource.resourceKind == "content",
            let generation = resource.generation,
            await resourceLeaseRegistry.contains(resource, paneId: paneId)
        {
            let interest = BridgeContentDemandInterest.parse(url.absoluteString) ?? .unspecified
            await contentDemandAdmission.start(interest)
            await emitContent(
                emissionRequest: BridgeSchemeContentEmissionRequest(
                    handleId: resource.opaqueId,
                    generation: BridgeReviewGeneration(generation),
                    url: url,
                    request: request,
                    readMethod: readMethod,
                    leasedResource: resource,
                    interest: interest
                ),
                continuation: continuation
            )
            await contentDemandAdmission.finish(interest)
            return
        }
        do {
            try Task.checkCancellation()
            continuation.finish(throwing: BridgeSchemeError.invalidRoute(Self.invalidRouteReason))
        } catch {
            continuation.finish(throwing: error)
        }
    }

    // MARK: - Path Classification

    /// Categorization of an `agentstudio://` URL into one of the supported route types.
    enum PathType: Equatable {
        /// Bundled React app asset at the given relative path (e.g. "index.html", "assets/main.js").
        case app(String)
        /// Protocol-scoped content request that must match an active transport lease.
        case leasedContent(BridgeTransportResourceURL)
        /// Dedicated telemetry ingestion route.
        case telemetryBatch
        /// Capability-bound product command, metadata stream, or content route.
        case product
        /// Unrecognized or malicious route (e.g. path traversal, wrong host).
        case invalid
    }

    /// Classify a URL string into app asset, resource request, or invalid.
    ///
    /// Security: Rejects path traversal attempts by checking decoded path segments
    /// for ".." components. Uses `URL.path()` which percent-decodes, so encoded
    /// traversal like `%2e%2e` is caught after decoding. Segment-based checking
    /// avoids false-rejecting benign paths containing dots (e.g. `my.file.txt`).
    static func classifyPath(
        _ urlString: String,
        allowedResourceKindsByProtocol: [String: Set<String>] =
            BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
    ) -> PathType {
        guard let url = URL(string: urlString),
            url.scheme == "agentstudio"
        else {
            return .invalid
        }

        let host = url.host() ?? ""
        // Stable-decode: iteratively percent-decode until the string stops changing.
        // Catches double-encoding attacks like %252e%252e → %2e%2e → ".."
        var path = url.path()
        var previous: String?
        while path != previous {
            previous = path
            path = path.removingPercentEncoding ?? path
        }

        // Reject path traversal — check for ".." as a complete path segment.
        // Segment-based check avoids false-rejecting benign filenames like "my..config.js".
        let segments = path.split(separator: "/")
        if segments.contains("..") {
            return .invalid
        }

        switch host {
        case "app":
            let relativePath = String(path.dropFirst())  // remove leading /
            guard !relativePath.isEmpty else { return .invalid }
            return .app(relativePath)

        case "telemetry":
            return path == "/batch" ? .telemetryBatch : .invalid

        case "rpc":
            let absoluteURL = url.absoluteString
            guard
                absoluteURL == BridgeProductWireContract.commandRoute
                    || absoluteURL == BridgeProductWireContract.streamRoute
                    || absoluteURL == BridgeProductWireContract.contentRoute
            else {
                return .invalid
            }
            return .product

        case "resource":
            guard
                let resource = BridgeTransportResourceURL.parse(
                    urlString,
                    allowedResourceKindsByProtocol: allowedResourceKindsByProtocol
                )
            else {
                return .invalid
            }
            return .leasedContent(resource)

        default:
            return .invalid
        }
    }

    enum BridgeSchemeReadMethod {
        case get
        case head
        case options
        case post
    }

    private func startTelemetryBatchReplyTask(
        url: URL,
        request: URLRequest,
        readMethod: BridgeSchemeReadMethod,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) {
        let task = Task {
            await emitTelemetryBatch(
                url: url,
                request: request,
                readMethod: readMethod,
                continuation: continuation
            )
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
    }

    private func emitTelemetryBatch(
        url: URL,
        request: URLRequest,
        readMethod: BridgeSchemeReadMethod,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) async {
        guard readMethod == .post else {
            continuation.finish(throwing: BridgeSchemeError.invalidRequest("Unsupported telemetry method"))
            return
        }
        guard let telemetrySessionOwner else {
            continuation.finish(throwing: BridgeSchemeError.invalidRoute(Self.invalidRouteReason))
            return
        }
        let presentedCapability = request.value(
            forHTTPHeaderField: BridgeTelemetryWorkerWireContract.capabilityHeaderName
        )
        guard await telemetrySessionOwner.authorizes(presentedCapability) else {
            emitTelemetryHTTPResponse(
                url: url,
                statusCode: 403,
                body: nil,
                continuation: continuation
            )
            return
        }
        guard request.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true
        else {
            continuation.finish(throwing: BridgeSchemeError.invalidRequest("Unsupported telemetry content type"))
            return
        }
        let body: Data
        switch BridgeProductBoundedRequestBodyReader(maximumBytes: BridgeTelemetryWorkerPolicy.live.batchMaxBytes)
            .read(request)
        {
        case .body(let admittedBody, _):
            body = admittedBody
        case .oversized:
            emitTelemetryHTTPResponse(
                url: url,
                statusCode: 413,
                body: nil,
                continuation: continuation
            )
            return
        case .invalid, .missing:
            continuation.finish(throwing: BridgeSchemeError.invalidRequest("Missing telemetry body"))
            return
        }
        let admission = await telemetrySessionOwner.admit(
            presentedCapability: presentedCapability,
            encodedBody: body
        )
        switch admission {
        case .unauthorized:
            emitTelemetryHTTPResponse(
                url: url,
                statusCode: 403,
                body: nil,
                continuation: continuation
            )
        case .bodyTooLarge:
            emitTelemetryHTTPResponse(
                url: url,
                statusCode: 413,
                body: nil,
                continuation: continuation
            )
        case .response(let response):
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let responseBody = try? encoder.encode(response) else {
                continuation.finish(throwing: BridgeSchemeError.invalidRequest("Telemetry response encoding failed"))
                return
            }
            emitTelemetryHTTPResponse(
                url: url,
                statusCode: 200,
                body: responseBody,
                continuation: continuation
            )
        }
    }

    private func emitTelemetryHTTPResponse(
        url: URL,
        statusCode: Int,
        body: Data?,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) {
        let headers = [
            "Access-Control-Allow-Headers":
                "Content-Type, traceparent, \(BridgeTelemetryWorkerWireContract.capabilityHeaderName)",
            "Access-Control-Allow-Methods": Self.allowedMethods(for: .telemetryBatch),
            "Access-Control-Allow-Origin": "*",
            "Content-Length": String(body?.count ?? 0),
            "Content-Type": "application/json; charset=utf-8",
        ]
        guard
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
        else {
            continuation.finish(throwing: BridgeSchemeError.invalidRequest("Telemetry response failed"))
            return
        }
        continuation.yield(.response(response))
        if let body {
            continuation.yield(.data(body))
        }
        continuation.finish()
    }

    private func emitContent(
        emissionRequest: BridgeSchemeContentEmissionRequest,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) async {
        if emissionRequest.readMethod == .head {
            await emitContentHead(emissionRequest: emissionRequest, continuation: continuation)
            return
        }
        let traceContext = Self.traceContext(from: emissionRequest.request)
        let hasTraceparentHeader = Self.traceparentHeader(from: emissionRequest.request) != nil
        let loadStart = ContinuousClock.now
        do {
            let handle = try await contentStore.metadata(
                handleId: emissionRequest.handleId,
                requestedGeneration: emissionRequest.generation
            )
            let expectedContentLength = Self.expectedContentLength(for: handle)
            guard
                await resourceLeaseRegistry.contains(
                    emissionRequest.leasedResource,
                    paneId: paneId,
                    contentLength: expectedContentLength
                )
            else {
                continuation.finish(throwing: BridgeSchemeError.invalidRoute(Self.invalidRouteReason))
                return
            }
            guard
                try await emitContentResponse(
                    handle: handle,
                    emissionRequest: emissionRequest,
                    expectedContentLength: expectedContentLength,
                    continuation: continuation
                )
            else {
                continuation.finish(throwing: BridgeSchemeError.invalidRoute(Self.invalidRouteReason))
                return
            }
            if emissionRequest.readMethod == .get {
                let observation = try await streamContentBody(
                    emissionRequest: emissionRequest,
                    expectedContentLength: expectedContentLength,
                    continuation: continuation
                )
                await recordContentLoadTelemetry(
                    observation: observation,
                    traceContext: traceContext,
                    hasTraceparentHeader: hasTraceparentHeader,
                    phase: "success",
                    durationMilliseconds: Self.milliseconds(from: loadStart.duration(to: ContinuousClock.now)),
                    interest: emissionRequest.interest
                )
            }
            continuation.finish()
        } catch let failure as BridgeContentLoadObservedFailure {
            await recordContentLoadTelemetry(
                observation: failure.observation,
                traceContext: traceContext,
                hasTraceparentHeader: hasTraceparentHeader,
                phase: "error",
                durationMilliseconds: Self.milliseconds(from: loadStart.duration(to: ContinuousClock.now)),
                interest: emissionRequest.interest
            )
            continuation.finish(throwing: failure.underlyingError)
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func emitContentResponse(
        handle: BridgeContentHandle,
        emissionRequest: BridgeSchemeContentEmissionRequest,
        expectedContentLength: Int?,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) async throws -> Bool {
        try Task.checkCancellation()
        await beforeContentEmission?()
        await contentDemandAdmission.waitForBackgroundTurn(emissionRequest.interest)
        return await resourceLeaseRegistry.performWhileLeased(
            emissionRequest.leasedResource,
            paneId: paneId,
            contentLength: expectedContentLength,
            {
                continuation.yield(
                    .response(
                        Self.response(
                            url: emissionRequest.url,
                            mimeType: handle.mimeType,
                            expectedContentLength: expectedContentLength
                        )))
            }
        )
    }

    private func streamContentBody(
        emissionRequest: BridgeSchemeContentEmissionRequest,
        expectedContentLength: Int?,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) async throws -> BridgeContentLoadObservation {
        guard
            await resourceLeaseRegistry.contains(
                emissionRequest.leasedResource,
                paneId: paneId,
                contentLength: expectedContentLength
            )
        else {
            throw BridgeSchemeError.invalidRoute(Self.invalidRouteReason)
        }
        let byteCounter = BridgeSchemeResourceByteCounter()
        let observed = try await contentStore.streamObserved(
            handleId: emissionRequest.handleId,
            requestedGeneration: emissionRequest.generation,
            chunkByteCount: Self.resourceChunkByteCount
        ) { chunk in
            try Task.checkCancellation()
            await beforeContentEmission?()
            await contentDemandAdmission.waitForBackgroundTurn(emissionRequest.interest)
            let totalBytesRead = byteCounter.add(chunk.count)
            let didEmitChunk = await resourceLeaseRegistry.performWhileLeased(
                emissionRequest.leasedResource,
                paneId: paneId,
                contentLength: totalBytesRead,
                {
                    continuation.yield(.data(chunk))
                }
            )
            guard didEmitChunk else {
                throw BridgeSchemeError.invalidRoute(Self.invalidRouteReason)
            }
        }
        return observed.observation
    }

    private func emitContentHead(
        emissionRequest: BridgeSchemeContentEmissionRequest,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) async {
        do {
            let handle = try await contentStore.metadata(
                handleId: emissionRequest.handleId,
                requestedGeneration: emissionRequest.generation
            )
            let expectedContentLength = Self.expectedContentLength(for: handle)
            guard
                await resourceLeaseRegistry.contains(
                    emissionRequest.leasedResource,
                    paneId: paneId,
                    contentLength: expectedContentLength
                )
            else {
                continuation.finish(throwing: BridgeSchemeError.invalidRoute(Self.invalidRouteReason))
                return
            }
            await beforeContentEmission?()
            await contentDemandAdmission.waitForBackgroundTurn(emissionRequest.interest)
            guard
                await resourceLeaseRegistry.performWhileLeased(
                    emissionRequest.leasedResource,
                    paneId: paneId,
                    contentLength: expectedContentLength,
                    {
                        continuation.yield(
                            .response(
                                Self.response(
                                    url: emissionRequest.url,
                                    mimeType: handle.mimeType,
                                    expectedContentLength: expectedContentLength
                                )))
                    }
                )
            else {
                continuation.finish(throwing: BridgeSchemeError.invalidRoute(Self.invalidRouteReason))
                return
            }
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func recordContentLoadTelemetry(
        observation: BridgeContentLoadObservation,
        traceContext: BridgeTraceContext?,
        hasTraceparentHeader: Bool,
        phase: String,
        durationMilliseconds: Double,
        transport: String = "content",
        interest: BridgeContentDemandInterest = .unspecified
    ) async {
        guard let telemetryRecorder else {
            return
        }
        await telemetryRecorder.record(
            sample: BridgeTelemetrySample(
                scope: .swift,
                name: "performance.bridge.swift.content_load",
                durationMilliseconds: durationMilliseconds,
                traceContext: traceContext,
                stringAttributes: [
                    "agentstudio.bridge.cache.result": observation.cacheResult.rawValue,
                    "agentstudio.bridge.content.correlation_mode": traceContext == nil ? "summary" : "traceparent",
                    "agentstudio.bridge.content.interest": interest.rawValue,
                    "agentstudio.bridge.content.role": observation.role?.rawValue ?? "unknown",
                    "agentstudio.bridge.generation.relation": observation.generationRelation.rawValue,
                    "agentstudio.bridge.phase": phase,
                    "agentstudio.bridge.plane": BridgeTelemetryPlane.data.rawValue,
                    "agentstudio.bridge.priority": BridgeTelemetryPriority.hot.rawValue,
                    "agentstudio.bridge.slice": BridgeTelemetrySlice.contentFetch.rawValue,
                    "agentstudio.bridge.transport": transport,
                ],
                numericAttributes: [
                    "agentstudio.bridge.content.byte_size_bucket": Double(observation.byteSizeBucket),
                    "agentstudio.bridge.content.line_count_bucket": Double(observation.lineCountBucket),
                ],
                booleanAttributes: [
                    "agentstudio.bridge.cache_hit": observation.cacheResult == .cacheHit,
                    "agentstudio.bridge.content.binary": observation.isBinary,
                    "agentstudio.bridge.content.stale": observation.isStale,
                    "agentstudio.bridge.header_missing": !hasTraceparentHeader,
                    "agentstudio.bridge.header_supported": traceContext != nil,
                ]
            ),
            receivedAtUnixNano: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
    }

    private func emitLeasedDataChunks(
        _ data: Data,
        leasedResource: BridgeTransportResourceURL,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) async throws -> Bool {
        var offset = 0
        while offset < data.count {
            let endOffset = min(offset + Self.resourceChunkByteCount, data.count)
            let chunk = data.subdata(in: offset..<endOffset)
            try Task.checkCancellation()
            await beforeContentEmission?()
            let didEmitChunk = await resourceLeaseRegistry.performWhileLeased(
                leasedResource,
                paneId: paneId,
                contentLength: data.count,
                {
                    continuation.yield(.data(chunk))
                }
            )
            guard didEmitChunk else {
                return false
            }
            offset = endOffset
        }
        return true
    }

    private static func milliseconds(from duration: Duration) -> Double {
        AgentStudioPerformanceTraceRecorder.milliseconds(from: duration)
    }

    // MARK: - MIME Type Resolution

    /// Resolve MIME type from file extension.
    ///
    /// Covers the common web asset types served by a bundled React app.
    /// Unknown extensions default to `application/octet-stream`.
    static func mimeType(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html"
        case "js", "mjs": return "application/javascript"
        case "css": return "text/css"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "wasm": return "application/wasm"
        default: return "application/octet-stream"
        }
    }

    static func textEncodingName(for mimeType: String) -> String? {
        if mimeType.hasPrefix("text/") || mimeType == "application/json" || mimeType == "application/javascript" {
            return "utf-8"
        }
        return nil
    }

    static func allowedMethods(for classification: PathType) -> String {
        classification.supportsPostRequests ? "OPTIONS, POST" : "GET, HEAD, OPTIONS"
    }

    static func response(
        url: URL,
        mimeType: String,
        expectedContentLength: Int?,
        allowedMethods: String = "GET, HEAD, OPTIONS"
    ) -> URLResponse {
        var headers = [
            "Access-Control-Allow-Headers": "Content-Type, traceparent",
            "Access-Control-Allow-Methods": allowedMethods,
            "Access-Control-Allow-Origin": "*",
            "Content-Type": mimeType,
        ]
        if let expectedContentLength {
            headers["Content-Length"] = String(expectedContentLength)
        }
        if let textEncodingName = textEncodingName(for: mimeType) {
            headers["Content-Type"] = "\(mimeType); charset=\(textEncodingName)"
        }
        return HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )
            ?? URLResponse(
                url: url,
                mimeType: mimeType,
                expectedContentLength: expectedContentLength ?? -1,
                textEncodingName: textEncodingName(for: mimeType)
            )
    }
}

extension BridgeSchemeHandler {
    fileprivate static func expectedContentLength(for handle: BridgeContentHandle) -> Int? {
        handle.sizeBytesIsExact ? handle.sizeBytes : nil
    }

    fileprivate static func byteSizeBucket(for byteSize: Int) -> Int {
        guard byteSize > 0 else {
            return 0
        }
        var bucket = 1024
        while bucket < byteSize, bucket < 64 * 1024 * 1024 {
            bucket *= 2
        }
        return bucket
    }

    fileprivate static func isBinaryMimeType(_ mimeType: String) -> Bool {
        if mimeType.hasPrefix("text/") {
            return false
        }
        switch mimeType {
        case "application/json", "application/javascript", "application/xml", "image/svg+xml":
            return false
        default:
            return true
        }
    }

    fileprivate static func readMethod(from httpMethod: String?) -> BridgeSchemeReadMethod? {
        switch httpMethod?.uppercased() ?? "GET" {
        case "GET": .get
        case "HEAD": .head
        case "OPTIONS": .options
        case "POST": .post
        default: nil
        }
    }

    fileprivate static func traceContext(from request: URLRequest) -> BridgeTraceContext? {
        guard let traceparent = traceparentHeader(from: request) else {
            return nil
        }
        return try? BridgeTraceContext.parseTraceparent(traceparent)
    }

    fileprivate static func traceparentHeader(from request: URLRequest) -> String? {
        request.value(forHTTPHeaderField: "traceparent")
    }
}

private final class BridgeSchemeResourceByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func add(_ byteCount: Int) -> Int {
        lock.withLock {
            value += byteCount
            return value
        }
    }
}

// MARK: - Errors

/// Errors produced by the bridge scheme handler when a URL cannot be served.
enum BridgeSchemeError: Error, Sendable {
    /// The request was malformed (e.g. missing URL).
    case invalidRequest(String)
    /// The URL matched the `agentstudio` scheme but the route is unrecognized.
    case invalidRoute(String)
    /// The URL requested a valid app route but no packaged app asset exists.
    case assetNotFound(String)
}
