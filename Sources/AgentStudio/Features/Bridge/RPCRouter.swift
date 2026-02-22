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

    private var handlers: [String: @MainActor ([String: Any]) async throws -> Void] = [:]
    private var seenCommandIds: [String] = []
    private let maxCommandIdHistory = 100

    // MARK: - Error Callback

    /// Error callback: (code, message, id?)
    ///
    /// Standard JSON-RPC 2.0 error codes:
    /// - `-32700`: Parse error
    /// - `-32600`: Invalid request (missing method, batch array)
    /// - `-32601`: Method not found
    var onError: ((Int, String, Any?) -> Void)?

    // MARK: - Registration

    /// Register a handler for a JSON-RPC method name.
    ///
    /// The handler receives the `params` dictionary from the JSON-RPC envelope.
    /// Only one handler per method name; later registrations replace earlier ones.
    func register(_ method: String, handler: @escaping @MainActor ([String: Any]) async throws -> Void) {
        handlers[method] = handler
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

        // Step 2: Parse envelope — require method field
        guard let dict = raw as? [String: Any],
            let method = dict["method"] as? String
        else {
            let requestId = (raw as? [String: Any])?["id"]
            onError?(-32_600, "Invalid request: missing method", requestId)
            return
        }

        // Step 3: Check __commandId dedup (sliding window)
        if let commandId = dict["__commandId"] as? String {
            if seenCommandIds.contains(commandId) {
                return  // Idempotent — already processed
            }
            seenCommandIds.append(commandId)
            if seenCommandIds.count > maxCommandIdHistory {
                seenCommandIds.removeFirst()
            }
        }

        // Step 4: Find and execute handler
        guard let handler = handlers[method] else {
            let requestId = dict["id"]
            onError?(-32_601, "Method not found: \(method)", requestId)
            return
        }

        let params = dict["params"] as? [String: Any] ?? [:]
        try await handler(params)
    }
}
