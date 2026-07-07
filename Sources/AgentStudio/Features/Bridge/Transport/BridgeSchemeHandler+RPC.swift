import Foundation
import WebKit

@MainActor
protocol BridgeSchemeRPCDispatching: AnyObject, Sendable {
    func dispatchBridgeSchemeRPC(json: String) async -> String?
}

@MainActor
final class BridgeSchemeRPCDispatcher: BridgeSchemeRPCDispatching {
    var handler: (@MainActor (String) async -> String?)?

    func dispatchBridgeSchemeRPC(json: String) async -> String? {
        await handler?(json)
    }
}

extension BridgeSchemeHandler.PathType {
    var supportsPostRequests: Bool {
        switch self {
        case .telemetryBatch, .rpcCommand:
            true
        case .app, .leasedContent, .invalid:
            false
        }
    }
}

extension BridgeSchemeHandler {
    private static let maxEncodedRPCCommandBytes = 64 * 1024

    func startRPCCommandReplyTask(
        url: URL,
        request: URLRequest,
        readMethod: BridgeSchemeReadMethod,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) {
        let task = Task {
            await emitRPCCommand(
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

    private func emitRPCCommand(
        url: URL,
        request: URLRequest,
        readMethod: BridgeSchemeReadMethod,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) async {
        guard readMethod == .post else {
            continuation.finish(throwing: BridgeSchemeError.invalidRequest("Unsupported RPC method"))
            return
        }
        guard request.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true
        else {
            continuation.finish(throwing: BridgeSchemeError.invalidRequest("Unsupported RPC content type"))
            return
        }
        guard let body = request.httpBody else {
            continuation.finish(throwing: BridgeSchemeError.invalidRequest("Missing RPC body"))
            return
        }
        guard body.count <= Self.maxEncodedRPCCommandBytes else {
            continuation.finish(throwing: BridgeSchemeError.invalidRequest("RPC body too large"))
            return
        }
        guard let rpcDispatcher else {
            continuation.finish(throwing: BridgeSchemeError.invalidRoute("rpc-dispatcher-unavailable"))
            return
        }
        guard
            let requestJSON = String(data: body, encoding: .utf8),
            (try? JSONSerialization.jsonObject(with: body)) != nil
        else {
            continuation.finish(throwing: BridgeSchemeError.invalidRequest("Invalid RPC JSON"))
            return
        }

        let responseJSON = await rpcDispatcher.dispatchBridgeSchemeRPC(json: requestJSON)
        let responseData = Data((responseJSON ?? "").utf8)
        continuation.yield(
            .response(
                Self.response(
                    url: url,
                    mimeType: "application/json",
                    expectedContentLength: responseData.count,
                    allowedMethods: Self.allowedMethods(for: .rpcCommand)
                )))
        if !responseData.isEmpty {
            continuation.yield(.data(responseData))
        }
        continuation.finish()
    }
}
