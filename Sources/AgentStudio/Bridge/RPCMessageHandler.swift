import Foundation
import WebKit

/// Receives postMessage from the bridge content world and forwards validated JSON upstream.
///
/// Registered in the bridge content world only — page world scripts cannot access this handler.
/// Bridge relay sends `JSON.stringify(envelope)` via `window.webkit.messageHandlers.rpc.postMessage(...)`,
/// so the WKScriptMessage body arrives as a String.
///
/// The `onValidJSON` callback is set by `BridgePaneController` to forward to `RPCRouter.dispatch`.
/// Using a closure instead of a direct RPCRouter reference keeps this handler decoupled and testable.
///
/// Design doc §4.2, §9.3.
final class RPCMessageHandler: NSObject, WKScriptMessageHandler {

    /// Called on the main thread when a valid JSON string is extracted from a postMessage body.
    /// Set by the owning controller to wire into `RPCRouter.dispatch(json:)`.
    ///
    /// Using `nonisolated(unsafe)` because `WKScriptMessageHandler.userContentController(_:didReceive:)`
    /// is nonisolated, but this property is set once during setup and read from the main thread only.
    nonisolated(unsafe) var onValidJSON: (@MainActor (String) async -> Void)?

    // MARK: - JSON Extraction

    /// Extract and validate a JSON string from a WKScriptMessage body.
    ///
    /// Returns the original JSON string if valid, `nil` otherwise.
    ///
    /// `postMessage` can deliver any JS value (string, number, object, array, null).
    /// The bridge relay sends `JSON.stringify`'d strings, so we require `String` type.
    /// Non-string bodies (NSDictionary, NSNumber, NSArray) are rejected.
    static func extractJSON(from body: Any) -> String? {
        guard let jsonString = body as? String,
              !jsonString.isEmpty else {
            return nil
        }

        // Validate the string is parseable JSON.
        // JSONSerialization handles edge cases (BOM, leading whitespace, etc.)
        // that manual prefix checking would miss.
        guard let data = jsonString.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return nil
        }

        return jsonString
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let json = Self.extractJSON(from: message.body) else {
            return // Silently drop non-JSON messages
        }

        // Forward to upstream handler on main actor.
        // Fire-and-forget: errors are handled by the router's onError callback,
        // not propagated back through the message handler.
        Task { @MainActor in
            await onValidJSON?(json)
        }
    }
}
