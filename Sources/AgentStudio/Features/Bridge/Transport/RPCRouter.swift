import Foundation
import os.log

/// Routes incoming JSON-RPC messages to registered method handlers.
///
/// Handles dedup via `__commandId` sliding window, batch rejection,
/// and error reporting. This is the command channel entry point.
///
/// See bridge architecture docs for command format, batch behavior, and runtime integration.
private let rpcRouterLogger = Logger(subsystem: "com.agentstudio", category: "RPCRouter")

private enum RPCErrorCode: Int, Sendable {
    case parseError = -32_700
    case invalidRequest = -32_600
    case methodNotFound = -32_601
    case invalidParams = -32_602
    case internalError = -32_603
    case bridgeNotReady = -32_004
}

@MainActor
final class RPCRouter {

    // MARK: - Private State

    private var handlers: [String: any AnyRPCMethodHandler] = [:]
    private var seenCommandIdSet: Set<String> = []
    private var seenCommandIdRing: [String?]
    private var seenCommandIdWriteIndex = 0
    private var seenCommandIdCount = 0
    private let maxCommandIdHistory: Int

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
    var onError: (@MainActor @Sendable (Int, String, RPCIdentifier?) -> Void) = { code, message, id in
        let requestID = id.map { String(describing: $0) } ?? "nil"
        rpcRouterLogger.warning("RPC error code=\(code) message=\(message) id=\(requestID)")
    }
    var onCommandAck: (@MainActor @Sendable (CommandAck) -> Void) = { ack in
        rpcRouterLogger.debug(
            "RPC ack commandId=\(ack.commandId) method=\(ack.method) status=\(ack.status.rawValue)"
        )
    }
    var onResponse: (@MainActor @Sendable (String) async -> Void) = { responseJSON in
        rpcRouterLogger.warning("RPC response dropped because onResponse is not configured: \(responseJSON)")
    }

    init(maxCommandIdHistory: Int = 100) {
        let boundedHistory = max(1, maxCommandIdHistory)
        self.maxCommandIdHistory = boundedHistory
        self.seenCommandIdRing = Array(repeating: nil, count: boundedHistory)
    }

    // MARK: - Registration

    /// Register a handler for a typed JSON-RPC method.
    ///
    /// Only one handler per method name; later registrations replace earlier ones.
    func register<M: RPCMethod>(
        method: M.Type,
        handler: @escaping @MainActor @Sendable (M.Params) async throws -> M.Result?
    ) {
        handlers[M.method] = M.makeHandler(handler)
    }

    // MARK: - Dispatch

    /// Parse and dispatch a raw JSON-RPC message string.
    ///
    /// Validates the envelope, rejects batch arrays, deduplicates by
    /// `__commandId`, and routes to the registered handler.
    ///
    /// JSON-RPC requests with an `id` emit direct response envelopes via `onResponse`.
    /// Notifications (no `id`) remain fire-and-forget and do not emit responses.
    func dispatch(json: String, isBridgeReady: Bool) async {
        let request: ParsedRPCRequest
        do {
            request = try parseRequestEnvelope(from: json)
        } catch let parseError as RequestEnvelopeParseError {
            await reportError(parseError.code, parseError.message, id: parseError.id)
            return
        } catch {
            await reportError(.parseError, "Parse error: \(errorMessage(from: error))", id: .null)
            return
        }

        guard isBridgeReady || request.method == BridgeReadyMethod.method else {
            rpcRouterLogger.info("[RPCRouter] dropped pre-ready command: \(request.method)")
            if request.requestId != nil {
                await reportError(.bridgeNotReady, "Bridge not ready: \(request.method)", id: request.requestId)
            }
            return
        }

        if shouldSkip(commandId: request.commandId) {
            return
        }

        guard let handler = handlers[request.method] else {
            await reportError(.methodNotFound, "Method not found: \(request.method)", id: request.requestId)
            return
        }

        do {
            let paramsData = try decodeParamsData(from: request.params)
            let resultData = try await handler.run(id: request.requestId, paramsData: paramsData)
            reportCommandAck(
                commandId: request.commandId,
                method: request.method,
                status: CommandAck.Status.ok,
                reason: nil
            )
            await emitSuccessResponseIfNeeded(id: request.requestId, resultData: resultData)
        } catch {
            let (rpcErrorCode, dispatchErrorMessage) = classifyDispatchError(error)
            reportCommandAck(
                commandId: request.commandId,
                method: request.method,
                status: CommandAck.Status.rejected,
                reason: errorMessage(from: error)
            )
            await reportError(rpcErrorCode, dispatchErrorMessage, id: request.requestId)
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
        let params: JSONRPCValue?
    }

    private struct RequestEnvelopeParseError: Error {
        let code: RPCErrorCode
        let message: String
        let id: RPCIdentifier?
    }

    private nonisolated func parseRequestEnvelope(from json: String) throws -> ParsedRPCRequest {
        guard let data = json.data(using: .utf8) else {
            throw RequestEnvelopeParseError(code: .parseError, message: "Parse error", id: .null)
        }

        let raw: JSONRPCValue
        do {
            raw = try JSONDecoder().decode(JSONRPCValue.self, from: data)
        } catch {
            throw RequestEnvelopeParseError(
                code: .parseError,
                message: "Parse error: \(error.localizedDescription)",
                id: .null
            )
        }

        if case .array = raw {
            throw RequestEnvelopeParseError(code: .invalidRequest, message: "Batch requests not supported", id: nil)
        }

        guard case .object(let dict) = raw else {
            throw RequestEnvelopeParseError(code: .invalidRequest, message: "Invalid request", id: nil)
        }

        let idValidation = parseRequestID(dict["id"])
        let requestId: RPCIdentifier?
        switch idValidation {
        case .invalid:
            throw RequestEnvelopeParseError(
                code: .invalidRequest,
                message: "Invalid request: invalid id",
                id: .null
            )
        case .missing:
            requestId = nil
        case .valid(let parsedID):
            requestId = parsedID
        }

        guard case .string("2.0")? = dict["jsonrpc"] else {
            throw RequestEnvelopeParseError(
                code: .invalidRequest,
                message: "Invalid request: unsupported jsonrpc version",
                id: requestId
            )
        }

        guard case .string(let method)? = dict["method"] else {
            throw RequestEnvelopeParseError(
                code: .invalidRequest,
                message: "Invalid request: missing method",
                id: requestId
            )
        }

        let commandId: String?
        if case .string(let rawCommandId)? = dict["__commandId"] {
            commandId = rawCommandId
        } else {
            commandId = nil
        }

        return ParsedRPCRequest(
            requestId: requestId,
            method: method,
            commandId: commandId,
            params: dict["params"]
        )
    }

    private func shouldSkip(commandId: String?) -> Bool {
        guard let commandId else {
            return false
        }
        guard !seenCommandIdSet.contains(commandId) else {
            rpcRouterLogger.debug("[RPCRouter] dedup skip commandId=\(commandId)")
            return true
        }

        if seenCommandIdCount == maxCommandIdHistory {
            if let evicted = seenCommandIdRing[seenCommandIdWriteIndex] {
                seenCommandIdSet.remove(evicted)
            }
        } else {
            seenCommandIdCount += 1
        }

        seenCommandIdRing[seenCommandIdWriteIndex] = commandId
        seenCommandIdWriteIndex = (seenCommandIdWriteIndex + 1) % maxCommandIdHistory
        seenCommandIdSet.insert(commandId)
        return false
    }

    private func classifyDispatchError(_ error: Error) -> (RPCErrorCode, String) {
        let rpcErrorCode: RPCErrorCode
        if error is RPCRouterParamsError {
            rpcErrorCode = .invalidParams
        } else if let dispatchError = error as? RPCMethodDispatchError {
            switch dispatchError {
            case .invalidParams:
                rpcErrorCode = .invalidParams
            case .handlerFailure:
                rpcErrorCode = .internalError
            }
        } else {
            rpcErrorCode = .internalError
        }

        let message: String
        switch rpcErrorCode {
        case .invalidParams:
            message = "Invalid params: \(errorMessage(from: error))"
        case .internalError:
            message = "Internal error: \(errorMessage(from: error))"
        default:
            message = "\(errorMessage(from: error))"
        }
        return (rpcErrorCode, message)
    }

    private func errorMessage(from error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }

        if let rpcMethodError = error as? RPCMethodDispatchError {
            switch rpcMethodError {
            case .invalidParams(let message),
                .handlerFailure(let message):
                return message
            }
        }

        return error.localizedDescription
    }

    private func reportCommandAck(
        commandId: String?,
        method: String,
        status: CommandAck.Status,
        reason: String?
    ) {
        guard let commandId else {
            return
        }
        onCommandAck(
            CommandAck(
                commandId: commandId,
                status: status,
                reason: reason,
                method: method,
                canonicalId: nil
            )
        )
    }

    private func reportError(_ code: RPCErrorCode, _ message: String, id: RPCIdentifier?) async {
        onError(code.rawValue, message, id)
        await emitErrorResponseIfNeeded(id: id, code: code.rawValue, message: message)
    }

    private func emitSuccessResponseIfNeeded(id: RPCIdentifier?, resultData: Data?) async {
        guard let id else {
            return
        }
        do {
            let responseJSON = try makeSuccessResponseJSON(id: id, resultData: resultData)
            await onResponse(responseJSON)
        } catch {
            let message = "Internal error: failed to encode response: \(self.errorMessage(from: error))"
            onError(RPCErrorCode.internalError.rawValue, message, id)
            do {
                let fallback = try makeErrorResponseJSON(
                    id: id,
                    code: RPCErrorCode.internalError.rawValue,
                    message: message
                )
                await onResponse(fallback)
            } catch {
                rpcRouterLogger.error(
                    "RPC success response and fallback error encoding both failed id=\(String(describing: id)): \(self.errorMessage(from: error))"
                )
            }
        }
    }

    private func emitErrorResponseIfNeeded(id: RPCIdentifier?, code: Int, message: String) async {
        guard let id else {
            return
        }
        do {
            let responseJSON = try makeErrorResponseJSON(id: id, code: code, message: message)
            await onResponse(responseJSON)
        } catch {
            let fallbackMessage = "Internal error: failed to encode error response: \(self.errorMessage(from: error))"
            rpcRouterLogger.error(
                "RPC error response encoding failed id=\(String(describing: id)) code=\(code): \(self.errorMessage(from: error))"
            )
            onError(RPCErrorCode.internalError.rawValue, fallbackMessage, id)
        }
    }

    private func makeSuccessResponseJSON(id: RPCIdentifier, resultData: Data?) throws -> String {
        var envelope: [String: JSONRPCValue] = [
            "jsonrpc": .string("2.0"),
            "id": responseJSONValue(for: id),
        ]
        envelope["result"] = try responseJSONValue(for: resultData)
        return try makeJSONString(from: envelope)
    }

    private func makeErrorResponseJSON(id: RPCIdentifier, code: Int, message: String) throws -> String {
        let envelope: [String: JSONRPCValue] = [
            "jsonrpc": .string("2.0"),
            "id": responseJSONValue(for: id),
            "error": .object([
                "code": .integer(Int64(code)),
                "message": .string(message),
            ]),
        ]
        return try makeJSONString(from: envelope)
    }

    private func makeJSONString(from object: [String: JSONRPCValue]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(JSONRPCValue.object(object))
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw RPCRouterResponseEncodingError.invalidUTF8
        }
        return encoded
    }

    private func responseJSONValue(for id: RPCIdentifier) -> JSONRPCValue {
        switch id {
        case .string(let value):
            return .string(value)
        case .integer(let value):
            return .integer(value)
        case .double(let value):
            return .double(value)
        case .null:
            return .null
        }
    }

    private nonisolated func decodeResultData(from resultData: Data?) throws -> JSONRPCValue {
        guard let resultData else {
            return .null
        }
        return try JSONDecoder().decode(JSONRPCValue.self, from: resultData)
    }

    private func responseJSONValue(for resultData: Data?) throws -> JSONRPCValue {
        try decodeResultData(from: resultData)
    }

    private nonisolated func parseRequestID(_ raw: JSONRPCValue?) -> RPCRequestIDState {
        guard let raw else {
            return .missing
        }

        switch raw {
        case .string(let value):
            return .valid(.string(value))
        case .integer(let value):
            return .valid(.integer(value))
        case .double(let value):
            if value.isFinite,
                value.rounded(.towardZero) == value,
                value >= Double(Int64.min),
                value <= Double(Int64.max)
            {
                return .valid(.integer(Int64(value)))
            }
            return .valid(.double(value))
        case .null:
            return .valid(.null)
        case .object, .array, .bool:
            return .invalid
        }
    }

    /// Return serialized `params` payload bytes for typed decoding.
    /// Returns `nil` when no params were provided so method defaulting can decide.
    private nonisolated func decodeParamsData(from rawParams: JSONRPCValue?) throws -> Data? {
        guard let rawParams else {
            return nil
        }

        if case .null = rawParams {
            throw RPCRouterParamsError.invalid("params is null")
        }

        return try JSONEncoder().encode(rawParams)
    }
}

private enum JSONRPCValue: Codable, Sendable {
    case object([String: Self])
    case array([Self])
    case string(String)
    case integer(Int64)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let object = try? container.decode([String: Self].self) {
            self = .object(object)
            return
        }
        if let array = try? container.decode([Self].self) {
            self = .array(array)
            return
        }
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        if let integer = try? container.decode(Int64.self) {
            self = .integer(integer)
            return
        }
        if let double = try? container.decode(Double.self) {
            self = .double(double)
            return
        }
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
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

private enum RPCRouterResponseEncodingError: Error {
    case invalidUTF8
}
