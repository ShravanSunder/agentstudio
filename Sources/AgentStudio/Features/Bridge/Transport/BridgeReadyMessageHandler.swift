import Foundation
import WebKit
import os.log

private let bridgeReadyMessageHandlerLogger = Logger(
    subsystem: "com.agentstudio",
    category: "BridgeReadyMessageHandler")

/// Receives the one-shot `bridge.ready` bootstrap request from the bridge content world.
///
/// Ordinary browser/native RPC uses the `agentstudio://rpc/command` scheme route.
/// This handler intentionally accepts only the bootstrap-ready envelope so the
/// script-message lane cannot stay alive as a parallel command transport.
final class BridgeReadyMessageHandler: NSObject, WKScriptMessageHandler {
    enum ReadyBootstrapMessage: Sendable, Equatable {
        case ready(requestId: String)
        case invalid(id: String?, message: String)
    }

    var onReadyRequest: (@MainActor @Sendable (ReadyBootstrapMessage) async -> Void)?

    nonisolated static func extractReadyRequestId(from body: Any) -> String? {
        guard case .ready(let requestId) = decodeReadyBootstrapMessage(from: body) else {
            return nil
        }
        return requestId
    }

    nonisolated static func decodeReadyBootstrapMessage(from body: Any) -> ReadyBootstrapMessage? {
        guard let jsonString = body as? String, !jsonString.isEmpty else {
            return nil
        }
        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any],
            dictionary["jsonrpc"] as? String == "2.0",
            dictionary["method"] as? String == BridgeReadyMethod.method
        else {
            return nil
        }
        guard dictionary.keys.contains("id") else {
            return .invalid(id: nil, message: "Invalid request")
        }
        guard let requestId = dictionary["id"] as? String, !requestId.isEmpty else {
            return .invalid(id: nil, message: "Invalid request: invalid id")
        }
        guard dictionary.keys.sorted() == ["id", "jsonrpc", "method", "params"],
            let params = dictionary["params"] as? [String: Any],
            params.isEmpty
        else {
            return .invalid(id: requestId, message: "Invalid request")
        }

        return .ready(requestId: requestId)
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let readyMessage = Self.decodeReadyBootstrapMessage(from: message.body) else {
            bridgeReadyMessageHandlerLogger.debug(
                "[BridgeReadyMessageHandler] dropped non-ready bootstrap message body type=\(type(of: message.body))")
            return
        }

        guard let callback = onReadyRequest else {
            bridgeReadyMessageHandlerLogger.warning(
                "[BridgeReadyMessageHandler] dropped bridge.ready because onReadyRequest is not configured")
            return
        }
        Task { @MainActor in
            await callback(readyMessage)
        }
    }
}
