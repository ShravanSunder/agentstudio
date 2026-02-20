import Foundation
import WebKit

/// URL scheme handler for `agentstudio://` custom scheme.
///
/// Routes:
/// - `agentstudio://app/*` — bundled React app assets (HTML, JS, CSS)
/// - `agentstudio://resource/file/<fileId>` — file contents on demand
///
/// Phase 1 implements the routing and MIME type logic. Actual asset resolution
/// from the app bundle comes in Phase 4.
struct BridgeSchemeHandler: URLSchemeHandler {
    let paneId: UUID

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
                // TODO: Phase 4 — resolve bundled React app asset from Bundle
                let html = "<html><head><title>Bridge</title></head><body>App: \(relativePath)</body></html>"
                let data = Data(html.utf8)
                let mime = Self.mimeType(for: relativePath)
                continuation.yield(
                    .response(
                        URLResponse(
                            url: url,
                            mimeType: mime,
                            expectedContentLength: data.count,
                            textEncodingName: "utf-8"
                        )))
                continuation.yield(.data(data))
                continuation.finish()

            case .resource(let fileId):
                // TODO: Phase 4 — resolve file content from workspace
                let placeholder = Data("resource:\(fileId)".utf8)
                continuation.yield(
                    .response(
                        URLResponse(
                            url: url,
                            mimeType: "application/octet-stream",
                            expectedContentLength: placeholder.count,
                            textEncodingName: nil
                        )))
                continuation.yield(.data(placeholder))
                continuation.finish()

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
        /// File resource request with the given file identifier.
        case resource(fileId: String)
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
            // Expected: /file/<fileId>
            let components = path.split(separator: "/")
            guard components.count == 2,
                components[0] == "file",
                !components[1].isEmpty
            else {
                return .invalid
            }
            return .resource(fileId: String(components[1]))

        default:
            return .invalid
        }
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
}

// MARK: - Errors

/// Errors produced by the bridge scheme handler when a URL cannot be served.
enum BridgeSchemeError: Error {
    /// The request was malformed (e.g. missing URL).
    case invalidRequest(String)
    /// The URL matched the `agentstudio` scheme but the route is unrecognized.
    case invalidRoute(String)
}
