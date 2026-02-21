import Foundation

/// Routes incoming JSON-RPC messages to registered method handlers.
///
/// Handles dedup via `__commandId` sliding window, batch rejection,
/// and error reporting. This is the command channel entry point.
///
/// Design doc §5.1 (command format), §5.5 (batch rejection), §9.2.
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
    var onError: ((Int, String, RPCIdentifier?) -> Void)?

    // MARK: - Registration

    /// Register a handler for a typed JSON-RPC method.
    ///
    /// Only one handler per method name; later registrations replace earlier ones.
    func register<M: RPCMethod>(method: M.Type, handler: @escaping (M.Params) async throws -> M.Result?) {
        handlers[M.method] = M.makeHandler(handler)
    }

    // MARK: - Dispatch

    /// Parse and dispatch a raw JSON-RPC message string.
    ///
    /// Validates the envelope, rejects batch arrays (§5.5), deduplicates by
    /// `__commandId`, and routes to the registered handler. Errors are reported
    /// via `onError` rather than thrown, following fire-and-forget notification semantics.
    func dispatch(json: String) async throws {
        guard let data = json.data(using: .utf8) else {
            onError?(-32_700, "Parse error", nil)
            return
        }

        // Step 1: Parse JSON — malformed JSON is a parse error (-32700)
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            onError?(-32_700, "Parse error: \(error.localizedDescription)", nil)
            return
        }

        // Step 1b: Detect batch (array) — reject per §5.5
        if raw is [Any] {
            onError?(-32_600, "Batch requests not supported", nil)
            return
        }

        guard let dict = raw as? [String: Any] else {
            onError?(-32_600, "Invalid request", nil)
            return
        }

        // Step 2: Parse request-id first so parity is preserved on every error.
        let requestId: RPCIdentifier?
        let idValidation = parseRequestID(dict["id"])
        switch idValidation {
        case .invalid:
            onError?(-32_600, "Invalid request: invalid id", .null)
            return
        case .missing:
            requestId = nil
        case .valid(let parsedID):
            requestId = parsedID
        }

        // Step 3: Validate JSON-RPC envelope metadata.
        guard dict["jsonrpc"] as? String == "2.0" else {
            onError?(-32_600, "Invalid request: unsupported jsonrpc version", requestId)
            return
        }

        // Step 4: Parse method field.
        guard let method = dict["method"] as? String else {
            onError?(-32_600, "Invalid request: missing method", requestId)
            return
        }

        // Step 5: Check __commandId dedup (sliding window)
        if let commandId = dict["__commandId"] as? String {
            if seenCommandIds.contains(commandId) {
                return  // Idempotent — already processed
            }
            seenCommandIds.append(commandId)
            if seenCommandIds.count > maxCommandIdHistory {
                seenCommandIds.removeFirst()
            }
        }

        // Step 6: Find and execute handler
        guard let handler = handlers[method] else {
            onError?(-32_601, "Method not found: \(method)", requestId)
            return
        }

        do {
            let paramsData = try decodeParamsData(from: dict["params"])
            _ = try await handler.run(id: requestId, paramsData: paramsData)
        } catch {
            onError?(-32_602, "Invalid params: \(error.localizedDescription)", requestId)
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
        case valid(RPCIdentifier?)
        case invalid
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
            throw RPCRouterParamsError.invalid
        }

        guard JSONSerialization.isValidJSONObject(rawParams) else {
            throw RPCRouterParamsError.invalid
        }

        let data = try JSONSerialization.data(withJSONObject: rawParams)

        return data
    }
}

private enum RPCRouterParamsError: Error {
    case invalid
}
