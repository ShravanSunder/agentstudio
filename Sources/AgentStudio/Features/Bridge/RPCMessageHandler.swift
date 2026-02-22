import Foundation
import WebKit
import os.log

private let messageHandlerLogger = Logger(subsystem: "com.agentstudio", category: "RPCMessageHandler")

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

    /// Callback invoked on the MainActor when `didReceive` extracts a valid JSON envelope.
    /// Set once by `BridgePaneController` during setup; routes to `RPCRouter.dispatch(json:)`.
    @MainActor var onValidJSON: (@MainActor (String) async -> Void)?

    // MARK: - JSON Extraction

    /// Extract and validate a JSON string from a WKScriptMessage body.
    ///
    /// Returns the original JSON string if valid, `nil` otherwise.
    ///
    /// `postMessage` can deliver any JS value (string, number, object, array, null).
    /// The bridge relay sends `JSON.stringify`'d strings, so we require `String` type.
    /// Non-string bodies (NSDictionary, NSNumber, NSArray) are rejected.
    nonisolated static func extractJSON(from body: Any) -> String? {
        guard let jsonString = body as? String,
            !jsonString.isEmpty
        else {
            return nil
        }

        // Validate the string is parseable JSON.
        // JSONSerialization handles edge cases (BOM, leading whitespace, etc.)
        // that manual prefix checking would miss.
        guard let data = jsonString.data(using: .utf8),
            (try? JSONSerialization.jsonObject(with: data)) != nil
        else {
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
            messageHandlerLogger.debug(
                "[RPCMessageHandler] dropped non-JSON message body type=\(type(of: message.body))")
            return
        }

        // Forward to upstream handler on main actor.
        // Fire-and-forget: errors are handled by the router's onError callback,
        // not propagated back through the message handler.
        Task { @MainActor in
            await onValidJSON?(json)
        }
    }
}
