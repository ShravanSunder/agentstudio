import Foundation
import os.log

/// Routes incoming JSON-RPC messages to registered method handlers.
///
/// Handles dedup via `__commandId` sliding window, batch rejection,
/// and error reporting. This is the command channel entry point.
///
/// Design doc §5.1 (command format), §5.5 (batch rejection), §9.2.
private let rpcRouterLogger = Logger(subsystem: "com.agentstudio", category: "RPCRouter")

@MainActor
final class RPCRouter {

    // MARK: - Private State

    private var handlers: [String: any AnyRPCMethodHandler] = [:]
    private var seenCommandIds: [String] = []
    private let maxCommandIdHistory = 100

    // MARK: - Error Callback

    /// Error callback: (code, message, id?)
    ///
    /// Standard JSON-RPC 2.0 error codes:
    /// - `-32700`: Parse error
    /// - `-32600`: Invalid request (missing method, batch array)
    /// - `-32601`: Method not found
    /// - `-32602`: Invalid params
    /// - `-32603`: Internal error
    ///
    /// Command-ack callback uses Swift-native command IDs found in the `__commandId` payload.
    var onError: ((Int, String, RPCIdentifier?) -> Void) = { code, message, id in
        let requestID = id.map { String(describing: $0) } ?? "nil"
        rpcRouterLogger.warning("RPC error code=\(code) message=\(message) id=\(requestID)")
    }
    var onCommandAck: ((CommandAck) -> Void)?

    // MARK: - Registration

    /// Register a handler for a typed JSON-RPC method.
    ///
    /// Only one handler per method name; later registrations replace earlier ones.
    func register<M: RPCMethod>(method: M.Type, handler: @escaping @Sendable (M.Params) async throws -> M.Result?) {
        handlers[M.method] = M.makeHandler(handler)
    }

    // MARK: - Dispatch

    /// Parse and dispatch a raw JSON-RPC message string.
    ///
    /// Validates the envelope, rejects batch arrays (§5.5), deduplicates by
    /// `__commandId`, and routes to the registered handler. Errors are reported
    /// via `onError` rather than thrown, following fire-and-forget notification semantics.
    func dispatch(json: String) async {
        guard let request = parseRequestEnvelope(from: json) else {
            return
        }

        if shouldSkip(commandId: request.commandId) {
            return
        }

        guard let handler = handlers[request.method] else {
            onError(-32_601, "Method not found: \(request.method)", request.requestId)
            return
        }

        do {
            let paramsData = try decodeParamsData(from: request.params)
            _ = try await handler.run(id: request.requestId, paramsData: paramsData)
            reportCommandAck(
                commandId: request.commandId,
                method: request.method,
                status: .ok,
                reason: nil
            )
        } catch {
            let (rpcErrorCode, errorMessage) = classifyDispatchError(error)
            reportCommandAck(
                commandId: request.commandId,
                method: request.method,
                status: .rejected,
                reason: error.localizedDescription
            )
            onError(rpcErrorCode, errorMessage, request.requestId)
        }
    }

    // MARK: - Envelope Parsing

    /// Strictly decode `id` only to supported JSON-RPC forms:
    /// - String
    /// - Number (stored as `Int64` when integral, else `Double`)
    /// - `null`
    /// - Omitted
    /// - Bool and other forms are invalid.
    private enum RPCRequestIDState {
        case missing
        case valid(RPCIdentifier)
        case invalid
    }

    private struct ParsedRPCRequest {
        let requestId: RPCIdentifier?
        let method: String
        let commandId: String?
        let params: Any?
    }

    private func parseRequestEnvelope(from json: String) -> ParsedRPCRequest? {
        guard let data = json.data(using: .utf8) else {
            onError(-32_700, "Parse error", nil)
            return nil
        }

        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            onError(-32_700, "Parse error: \(error.localizedDescription)", nil)
            return nil
        }

        if raw is [Any] {
            onError(-32_600, "Batch requests not supported", nil)
            return nil
        }

        guard let dict = raw as? [String: Any] else {
            onError(-32_600, "Invalid request", nil)
            return nil
        }

        let idValidation = parseRequestID(dict["id"])
        let requestId: RPCIdentifier?
        switch idValidation {
        case .invalid:
            onError(-32_600, "Invalid request: invalid id", .null)
            return nil
        case .missing:
            requestId = nil
        case .valid(let parsedID):
            requestId = parsedID
        }

        guard dict["jsonrpc"] as? String == "2.0" else {
            onError(-32_600, "Invalid request: unsupported jsonrpc version", requestId)
            return nil
        }

        guard let method = dict["method"] as? String else {
            onError(-32_600, "Invalid request: missing method", requestId)
            return nil
        }

        return ParsedRPCRequest(
            requestId: requestId,
            method: method,
            commandId: dict["__commandId"] as? String,
            params: dict["params"]
        )
    }

    private func shouldSkip(commandId: String?) -> Bool {
        guard let commandId else {
            return false
        }
        guard !seenCommandIds.contains(commandId) else {
            return true
        }
        seenCommandIds.append(commandId)
        if seenCommandIds.count > maxCommandIdHistory {
            seenCommandIds.removeFirst()
        }
        return false
    }

    private func classifyDispatchError(_ error: Error) -> (Int, String) {
        let rpcErrorCode: Int
        if error is RPCRouterParamsError {
            rpcErrorCode = -32_602
        } else if let dispatchError = error as? RPCMethodDispatchError {
            switch dispatchError {
            case .invalidParams:
                rpcErrorCode = -32_602
            case .handlerFailure:
                rpcErrorCode = -32_603
            }
        } else {
            rpcErrorCode = -32_603
        }

        let message: String
        switch rpcErrorCode {
        case -32_602:
            message = "Invalid params: \(error.localizedDescription)"
        case -32_603:
            message = "Internal error: \(error.localizedDescription)"
        default:
            message = "\(error.localizedDescription)"
        }
        return (rpcErrorCode, message)
    }

    private func reportCommandAck(
        commandId: String?,
        method: String,
        status: CommandStatus,
        reason: String?
    ) {
        guard let commandId else {
            return
        }
        onCommandAck?(
            CommandAck(
                commandId: commandId,
                status: status,
                reason: reason,
                method: method,
                canonicalId: nil
            )
        )
    }

    private func parseRequestID(_ raw: Any?) -> RPCRequestIDState {
        guard let raw else {
            return .missing
        }

        if let value = raw as? String {
            return .valid(.string(value))
        }
        if let value = raw as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .invalid
            }
            let integer = value.doubleValue
            if integer == trunc(integer) && integer >= Double(Int64.min) && integer <= Double(Int64.max) {
                return .valid(.integer(Int64(integer)))
            }
            return .valid(.double(integer))
        }
        if raw is NSNull {
            return .valid(.null)
        }

        return .invalid
    }

    /// Return serialized `params` payload bytes for typed decoding.
    /// Returns `nil` when no params were provided so method defaulting can decide.
    private func decodeParamsData(from rawParams: Any?) throws -> Data? {
        guard let rawParams else {
            return nil
        }

        if rawParams is NSNull {
            throw RPCRouterParamsError.invalid("params is null")
        }

        guard JSONSerialization.isValidJSONObject(rawParams) else {
            throw RPCRouterParamsError.invalid("params is not valid JSON")
        }

        let data = try JSONSerialization.data(withJSONObject: rawParams)

        return data
    }
}

private enum RPCRouterParamsError: Error, LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message):
            return message
        }
    }
}
