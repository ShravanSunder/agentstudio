import Foundation
import WebKit

/// URL scheme handler for bundled assets and capability-bound POST streams.
/// File and Review product bytes are owned by the pane product session; the
/// retired feature-resource GET route is intentionally absent.
struct BridgeSchemeHandler: URLSchemeHandler, Sendable {
    let appAssetStore: BridgeAppAssetStore
    let telemetrySessionOwner: BridgePaneTelemetrySessionOwner?
    let productSessionRouter: BridgeProductSchemeSessionRouter?

    private static let invalidRouteReason = "invalid-route"

    init(
        paneId _: UUID,
        appAssetStore: BridgeAppAssetStore = BridgeAppAssetStore(),
        telemetrySessionOwner: BridgePaneTelemetrySessionOwner? = nil,
        productSessionRouter: BridgeProductSchemeSessionRouter? = nil
    ) {
        self.appAssetStore = appAssetStore
        self.telemetrySessionOwner = telemetrySessionOwner
        self.productSessionRouter = productSessionRouter
    }

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

        let classification = Self.classifyPath(url.absoluteString)
        if readMethod == .options {
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
        let isProductPreflight = classification == .product
        continuation.yield(
            .response(
                Self.response(
                    url: url,
                    mimeType: "text/plain",
                    expectedContentLength: 0,
                    allowedMethods: Self.allowedMethods(for: classification),
                    allowedHeaders: isProductPreflight
                        ? "Content-Type, \(BridgeProductWireContract.capabilityHeaderName)"
                        : "Content-Type, traceparent",
                    statusCode: isProductPreflight ? 204 : 200
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
        continuation.onTermination = { _ in task.cancel() }
    }

    enum PathType: Equatable {
        case app(String)
        case telemetryBatch
        case product
        case invalid
    }

    static func classifyPath(_ urlString: String) -> PathType {
        guard let url = URL(string: urlString), url.scheme == "agentstudio" else {
            return .invalid
        }
        let host = url.host() ?? ""
        var path = url.path()
        var previous: String?
        while path != previous {
            previous = path
            path = path.removingPercentEncoding ?? path
        }
        guard !path.split(separator: "/").contains("..") else {
            return .invalid
        }

        switch host {
        case "app":
            let relativePath = String(path.dropFirst())
            return relativePath.isEmpty ? .invalid : .app(relativePath)
        case "telemetry":
            return path == "/batch" ? .telemetryBatch : .invalid
        case "rpc":
            switch url.absoluteString {
            case BridgeProductWireContract.commandRoute,
                BridgeProductWireContract.streamRoute,
                BridgeProductWireContract.contentRoute:
                return .product
            default:
                return .invalid
            }
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
        continuation.onTermination = { _ in task.cancel() }
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
            emitTelemetryHTTPResponse(url: url, statusCode: 403, body: nil, continuation: continuation)
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
            emitTelemetryHTTPResponse(url: url, statusCode: 413, body: nil, continuation: continuation)
            return
        case .invalid, .missing:
            continuation.finish(throwing: BridgeSchemeError.invalidRequest("Missing telemetry body"))
            return
        }
        switch await telemetrySessionOwner.admit(
            presentedCapability: presentedCapability,
            encodedBody: body
        ) {
        case .unauthorized:
            emitTelemetryHTTPResponse(url: url, statusCode: 403, body: nil, continuation: continuation)
        case .bodyTooLarge:
            emitTelemetryHTTPResponse(url: url, statusCode: 413, body: nil, continuation: continuation)
        case .response(let response):
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let responseBody = try? encoder.encode(response) else {
                continuation.finish(
                    throwing: BridgeSchemeError.invalidRequest("Telemetry response encoding failed")
                )
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

    static func mimeType(for filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "html", "htm": "text/html"
        case "js", "mjs": "application/javascript"
        case "css": "text/css"
        case "json": "application/json"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "woff2": "font/woff2"
        case "woff": "font/woff"
        case "wasm": "application/wasm"
        default: "application/octet-stream"
        }
    }

    static func textEncodingName(for mimeType: String) -> String? {
        if mimeType.hasPrefix("text/") || mimeType == "application/json"
            || mimeType == "application/javascript"
        {
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
        allowedMethods: String = "GET, HEAD, OPTIONS",
        allowedHeaders: String = "Content-Type, traceparent",
        statusCode: Int = 200
    ) -> URLResponse {
        var headers = [
            "Access-Control-Allow-Headers": allowedHeaders,
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
            statusCode: statusCode,
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
    fileprivate static func readMethod(from httpMethod: String?) -> BridgeSchemeReadMethod? {
        switch httpMethod?.uppercased() ?? "GET" {
        case "GET": .get
        case "HEAD": .head
        case "OPTIONS": .options
        case "POST": .post
        default: nil
        }
    }
}

enum BridgeSchemeError: Error, Sendable {
    case assetNotFound(String)
    case invalidRequest(String)
    case invalidRoute(String)
}
