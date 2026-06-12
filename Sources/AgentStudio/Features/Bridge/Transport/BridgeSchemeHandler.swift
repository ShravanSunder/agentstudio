import Foundation
import WebKit

/// URL scheme handler for `agentstudio://` custom scheme.
///
/// Routes:
/// - `agentstudio://app/*` — bundled React app assets (HTML, JS, CSS)
/// - `agentstudio://resource/content/<handleId>?generation=<n>` — file contents on demand
struct BridgeSchemeHandler: URLSchemeHandler {
    let paneId: UUID
    let contentStore: BridgeContentStore
    let appAssetStore: BridgeAppAssetStore

    init(
        paneId: UUID,
        contentStore: BridgeContentStore = BridgeContentStore(),
        appAssetStore: BridgeAppAssetStore = BridgeAppAssetStore()
    ) {
        self.paneId = paneId
        self.contentStore = contentStore
        self.appAssetStore = appAssetStore
    }

    // MARK: - URLSchemeHandler

    func reply(for request: URLRequest) -> some AsyncSequence<URLSchemeTaskResult, any Error> {
        AsyncThrowingStream<URLSchemeTaskResult, any Error> { continuation in
            guard let url = request.url else {
                continuation.finish(throwing: BridgeSchemeError.invalidRequest("Missing URL"))
                return
            }

            let classification = Self.classifyPath(url.absoluteString)
            switch classification {
            case .app(let relativePath):
                let task = Task {
                    do {
                        let asset = try await appAssetStore.load(relativePath: relativePath)
                        try Task.checkCancellation()
                        continuation.yield(
                            .response(
                                URLResponse(
                                    url: url,
                                    mimeType: asset.mimeType,
                                    expectedContentLength: asset.data.count,
                                    textEncodingName: Self.textEncodingName(for: asset.mimeType)
                                )))
                        try Task.checkCancellation()
                        continuation.yield(.data(asset.data))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in
                    task.cancel()
                }

            case .content(let handleId, let generation):
                let task = Task {
                    do {
                        let result = try await contentStore.load(
                            handleId: handleId,
                            requestedGeneration: generation
                        )
                        try Task.checkCancellation()
                        continuation.yield(
                            .response(
                                URLResponse(
                                    url: url,
                                    mimeType: result.mimeType,
                                    expectedContentLength: result.data.count,
                                    textEncodingName: Self.textEncodingName(for: result.mimeType)
                                )))
                        try Task.checkCancellation()
                        continuation.yield(.data(result.data))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in
                    task.cancel()
                }

            case .invalid:
                continuation.finish(throwing: BridgeSchemeError.invalidRoute(url.absoluteString))
            }
        }
    }

    // MARK: - Path Classification

    /// Categorization of an `agentstudio://` URL into one of the supported route types.
    enum PathType: Equatable {
        /// Bundled React app asset at the given relative path (e.g. "index.html", "assets/main.js").
        case app(String)
        /// Content resource request with a scoped handle and package generation guard.
        case content(handleId: String, generation: BridgeReviewGeneration)
        /// Unrecognized or malicious route (e.g. path traversal, wrong host).
        case invalid
    }

    /// Classify a URL string into app asset, resource request, or invalid.
    ///
    /// Security: Rejects path traversal attempts by checking decoded path segments
    /// for ".." components. Uses `URL.path()` which percent-decodes, so encoded
    /// traversal like `%2e%2e` is caught after decoding. Segment-based checking
    /// avoids false-rejecting benign paths containing dots (e.g. `my.file.txt`).
    static func classifyPath(_ urlString: String) -> PathType {
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

        case "resource":
            // Expected: /content/<handleId>?generation=<n>
            let components = path.split(separator: "/")
            guard components.count == 2,
                components[0] == "content",
                !components[1].isEmpty,
                let generation = generationValue(from: url)
            else {
                return .invalid
            }
            return .content(handleId: String(components[1]), generation: BridgeReviewGeneration(generation))

        default:
            return .invalid
        }
    }

    private static func generationValue(from url: URL) -> Int? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let value = components.queryItems?.first(where: { $0.name == "generation" })?.value,
            let generation = Int(value),
            generation >= 0
        else {
            return nil
        }
        return generation
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
