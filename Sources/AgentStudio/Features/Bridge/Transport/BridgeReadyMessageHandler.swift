import Foundation
import WebKit
import os.log

private let bridgeReadyMessageHandlerLogger = Logger(
    subsystem: "com.agentstudio",
    category: "BridgeReadyMessageHandler")

/// Receives the closed bootstrap-only request union from the bridge content world.
///
/// Ordinary browser/native RPC uses the `agentstudio://rpc/command` scheme route.
/// This handler intentionally accepts only the bootstrap-ready envelope so the
/// script-message lane cannot stay alive as a parallel command transport.
final class BridgeReadyMessageHandler: NSObject, WKScriptMessageHandler {
    enum ProductSessionBootstrapReason: String, Sendable, Equatable {
        case initial
        case workerReplacement
    }

    enum TelemetrySessionBootstrapReason: String, Sendable, Equatable {
        case initial
        case sidecarReplacement
    }

    enum BootstrapMessage: Sendable, Equatable {
        case ready(requestId: String)
        case productSessionBootstrap(requestId: String, reason: ProductSessionBootstrapReason)
        case telemetrySessionBootstrap(requestId: String, reason: TelemetrySessionBootstrapReason)
        case invalid(id: String?, message: String)
    }

    var onBootstrapRequest: (@MainActor @Sendable (BootstrapMessage) async -> Void)?

    nonisolated static func extractReadyRequestId(from body: Any) -> String? {
        guard case .ready(let requestId) = decodeBootstrapMessage(from: body) else {
            return nil
        }
        return requestId
    }

    nonisolated static func decodeBootstrapMessage(from body: Any) -> BootstrapMessage? {
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
            let method = dictionary["method"] as? String
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
            let params = dictionary["params"] as? [String: Any]
        else {
            return .invalid(id: requestId, message: "Invalid request")
        }
        switch method {
        case BridgeReadyMethod.method:
            return params.isEmpty
                ? .ready(requestId: requestId)
                : .invalid(id: requestId, message: "Invalid request")
        case "bridge.productSession.bootstrap":
            guard params.keys.sorted() == ["reason"],
                let rawReason = params["reason"] as? String,
                let reason = ProductSessionBootstrapReason(rawValue: rawReason)
            else {
                return .invalid(id: requestId, message: "Invalid request")
            }
            return .productSessionBootstrap(requestId: requestId, reason: reason)
        case "bridge.telemetrySession.bootstrap":
            guard params.keys.sorted() == ["reason"],
                let rawReason = params["reason"] as? String,
                let reason = TelemetrySessionBootstrapReason(rawValue: rawReason)
            else {
                return .invalid(id: requestId, message: "Invalid request")
            }
            return .telemetrySessionBootstrap(requestId: requestId, reason: reason)
        default:
            return nil
        }
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let bootstrapMessage = Self.decodeBootstrapMessage(from: message.body) else {
            bridgeReadyMessageHandlerLogger.debug(
                "[BridgeReadyMessageHandler] dropped non-ready bootstrap message body type=\(type(of: message.body))")
            return
        }

        guard let callback = onBootstrapRequest else {
            bridgeReadyMessageHandlerLogger.warning(
                "[BridgeReadyMessageHandler] dropped bootstrap request because callback is not configured")
            return
        }
        bridgeReadyMessageHandlerLogger.debug(
            "Received bootstrap request kind=\(String(describing: bootstrapMessage), privacy: .public)"
        )
        Task { @MainActor in
            await callback(bootstrapMessage)
        }
    }
}
