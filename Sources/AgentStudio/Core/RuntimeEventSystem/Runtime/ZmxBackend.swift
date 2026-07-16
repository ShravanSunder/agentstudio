import Foundation
import os

private let zmxLogger = Logger(subsystem: "com.agentstudio", category: "ZmxBackend")

// MARK: - Backend Types

struct ZmxCommandRetryPolicy: Sendable {
    let maxAttempts: Int
    let backoffs: [Duration]

    static let standard = Self(
        maxAttempts: 3,
        backoffs: [.milliseconds(100), .milliseconds(250)]
    )
    static let singleAttempt = Self(
        maxAttempts: 1,
        backoffs: []
    )

    init(maxAttempts: Int, backoffs: [Duration]) {
        self.maxAttempts = max(1, maxAttempts)
        self.backoffs = backoffs
    }

    func backoffBeforeAttempt(_ attempt: Int) -> Duration? {
        guard attempt > 1 else { return nil }
        let index = min(attempt - 2, max(backoffs.count - 1, 0))
        guard index >= 0, index < backoffs.count else { return nil }
        return backoffs[index]
    }
}

/// Identifies a backend session that backs a single terminal pane.
struct PaneSessionHandle: Equatable, Sendable, Codable, Hashable {
    let id: ZmxSessionID
}

/// Backend-agnostic protocol for managing per-pane terminal sessions.
protocol SessionBackend: Sendable {
    var isAvailable: Bool { get async }
    func createPaneSession(sessionID: ZmxSessionID) async throws -> PaneSessionHandle
    func attachCommand(for handle: PaneSessionHandle) -> String
    func destroyPaneSession(_ handle: PaneSessionHandle) async throws
    func healthCheck(_ handle: PaneSessionHandle) async -> Bool
    func socketExists() -> Bool
    func sessionExists(_ handle: PaneSessionHandle) async -> Bool
    func discoverOrphanSessions(excluding knownSessionIDs: Set<ZmxSessionID>) async -> [ZmxSessionID]
    func destroySessionByID(_ sessionID: ZmxSessionID) async throws
}

enum SessionBackendError: Error, LocalizedError {
    case notAvailable
    case timeout
    case operationFailed(String)
    case sessionNotFound(ZmxSessionID)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Session backend (zmx) is not available"
        case .timeout:
            return "Operation timed out"
        case .operationFailed(let detail):
            return "Operation failed: \(detail)"
        case .sessionNotFound(let id):
            return "Session not found: \(id.rawValue)"
        }
    }
}

enum ZmxSessionInventoryOutcome: Equatable, Sendable {
    case complete
    case unavailable(String)
    case skipped(String)

    var rawValue: String {
        switch self {
        case .complete:
            return "complete"
        case .unavailable:
            return "unavailable"
        case .skipped:
            return "skipped"
        }
    }
}

struct ZmxSessionInventorySnapshot: Equatable, Sendable {
    let outcome: ZmxSessionInventoryOutcome
    let sessionIDs: Set<ZmxSessionID>

    static func complete(_ sessionIDs: Set<ZmxSessionID>) -> Self {
        Self(outcome: .complete, sessionIDs: sessionIDs)
    }

    static func unavailable(_ reason: String) -> Self {
        Self(outcome: .unavailable(reason), sessionIDs: [])
    }
}

// MARK: - ZmxBackend

/// zmx-based implementation of SessionBackend.
/// Creates one zmx daemon per terminal pane using `ZMX_DIR` env var for isolation,
/// completely invisible to the user's own zmx sessions.
///
/// zmx has no pre-creation step — the daemon is spawned automatically
/// on first `zmx attach`. This means `createPaneSession` only builds a handle
/// (zero CLI calls), and the actual process starts when the Ghostty surface
/// executes the attach command.
final class ZmxBackend: SessionBackend {
    /// Default zmx directory for socket/state isolation.
    static let defaultZmxDir: String = {
        AppDataPaths.zmxDirectory().path
    }()

    /// Extract a session identifier from `zmx list` output.
    ///
    /// Supports:
    /// - legacy key/value lines: `session_name=<id>\t...`
    /// - current key/value lines: `name=<id>\t...`
    /// - short output: `<id>`
    static func extractSessionName(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace)
        for token in tokens {
            if token.hasPrefix("session_name=") {
                let value = token.dropFirst("session_name=".count)
                return value.isEmpty ? nil : String(value)
            }
            if token.hasPrefix("name=") {
                let value = token.dropFirst("name=".count)
                return value.isEmpty ? nil : String(value)
            }
        }

        guard let first = tokens.first, !first.contains("=") else { return nil }
        return String(first)
    }

    private let executor: ProcessExecutor
    private let zmxPath: String
    private let zmxDir: String
    private let retryPolicy: ZmxCommandRetryPolicy
    private let retrySleep: @Sendable (Duration) async -> Void

    init(
        executor: ProcessExecutor? = nil,
        zmxPath: String,
        zmxDir: String = ZmxBackend.defaultZmxDir,
        commandTimeoutSeconds: TimeInterval = 1.5,
        retryPolicy: ZmxCommandRetryPolicy = .standard,
        retrySleep: @escaping @Sendable (Duration) async -> Void = ZmxBackend.defaultRetrySleep
    ) {
        self.executor = executor ?? DefaultProcessExecutor(timeout: commandTimeoutSeconds)
        self.zmxPath = zmxPath
        self.zmxDir = zmxDir
        self.retryPolicy = retryPolicy
        self.retrySleep = retrySleep
    }

    // MARK: - Availability

    var isAvailable: Bool {
        get async {
            // zmx is available if the binary exists at the configured path
            FileManager.default.isExecutableFile(atPath: zmxPath)
        }
    }

    // MARK: - Pane Session Lifecycle

    /// Build a handle for a zmx session. No CLI call — zmx auto-creates on first attach.
    func createPaneSession(sessionID: ZmxSessionID) async throws -> PaneSessionHandle {
        // Ensure the zmx directory exists for socket isolation
        try FileManager.default.createDirectory(
            atPath: zmxDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        return PaneSessionHandle(id: sessionID)
    }

    func attachCommand(for handle: PaneSessionHandle) -> String {
        Self.buildAttachCommand(
            zmxPath: zmxPath,
            sessionID: handle.id,
            shell: Self.getDefaultShell()
        )
    }

    /// Build the zmx attach command.
    ///
    /// Format: `<zmxPath> attach <sessionId> <shell> -i -l`
    ///
    /// `ZMX_DIR` must be provided via process environment (Ghostty surface env vars).
    /// zmx auto-creates a daemon on first attach — no separate create step needed.
    static func buildAttachCommand(
        zmxPath: String,
        sessionID: ZmxSessionID,
        shell: String
    ) -> String {
        let escapedPath = shellEscape(zmxPath)
        let escapedId = shellEscape(sessionID.rawValue)
        let escapedShell = shellEscape(shell)
        return "\(escapedPath) attach \(escapedId) \(escapedShell) -i -l"
    }

    /// Double-quote a string for safe shell interpolation.
    ///
    /// This string is injected into an interactive shell via `sendText`, so it
    /// must survive one level of shell parsing in a double-quoted context.
    static func shellEscape(_ value: String) -> String {
        let escaped =
            value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "!", with: "\\!")
            .replacingOccurrences(of: "`", with: "\\`")
        return "\"\(escaped)\""
    }

    func destroyPaneSession(_ handle: PaneSessionHandle) async throws {
        let result = try await executeWithRetry(
            command: zmxPath,
            args: ["kill", handle.id.rawValue],
            operation: "zmx kill \(handle.id.rawValue)"
        )

        guard result.succeeded else {
            throw SessionBackendError.operationFailed(
                "Failed to destroy zmx session '\(handle.id.rawValue)': \(result.stderr)"
            )
        }
    }

    /// Check if the exact durable zmx identity is alive in `zmx list` output.
    func healthCheck(_ handle: PaneSessionHandle) async -> Bool {
        do {
            let result = try await executeWithRetry(
                command: zmxPath,
                args: ["list"],
                operation: "zmx list for healthCheck"
            )
            guard result.succeeded else { return false }
            let listedSessionIDs = Self.extractSessionIDs(from: result.stdout)
            let found = listedSessionIDs.contains(handle.id)
            if !found, !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                zmxLogger.debug("zmx list succeeded but session \(handle.id.rawValue) not found in output")
            }
            return found
        } catch {
            zmxLogger.debug("Health check failed for session \(handle.id.rawValue): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Discovery

    func socketExists() -> Bool {
        FileManager.default.fileExists(atPath: zmxDir)
    }

    func sessionExists(_ handle: PaneSessionHandle) async -> Bool {
        await healthCheck(handle)
    }

    /// Discover every live zmx identity exactly as listed by the isolated backend.
    func discoverAgentStudioSessions() async -> ZmxSessionInventorySnapshot {
        do {
            let result = try await executeWithRetry(
                command: zmxPath,
                args: ["list"],
                operation: "zmx list for AgentStudio session inventory"
            )

            guard result.succeeded else {
                return .unavailable(result.stderr)
            }

            return .complete(Self.extractSessionIDs(from: result.stdout))
        } catch {
            zmxLogger.warning("Failed to discover AgentStudio zmx sessions: \(error.localizedDescription)")
            return .unavailable(error.localizedDescription)
        }
    }

    /// Discover zmx sessions that are not tracked by the store.
    func discoverOrphanSessions(excluding knownSessionIDs: Set<ZmxSessionID>) async -> [ZmxSessionID] {
        let inventory = await discoverAgentStudioSessions()
        switch inventory.outcome {
        case .complete:
            return inventory.sessionIDs
                .filter { !knownSessionIDs.contains($0) }
                .sorted { $0.rawValue < $1.rawValue }
        case .unavailable, .skipped:
            return []
        }
    }

    func destroySessionByID(_ sessionID: ZmxSessionID) async throws {
        let result = try await executeWithRetry(
            command: zmxPath,
            args: ["kill", sessionID.rawValue],
            operation: "zmx kill \(sessionID.rawValue)"
        )

        guard result.succeeded else {
            throw SessionBackendError.operationFailed(
                "Failed to destroy zmx session '\(sessionID.rawValue)': \(result.stderr)"
            )
        }
    }

    // MARK: - Helpers

    private static func extractSessionIDs(from listOutput: String) -> Set<ZmxSessionID> {
        Set(
            listOutput
                .components(separatedBy: "\n")
                .compactMap(extractSessionName(from:))
                .compactMap(ZmxSessionID.init(restoring:))
        )
    }

    private static func defaultRetrySleep(_ duration: Duration) async {
        try? await Task.sleep(nanoseconds: duration.nanosecondsForTaskSleep)
    }

    private func executeWithRetry(
        command: String,
        args: [String],
        operation: String
    ) async throws -> ProcessResult {
        var lastError: Error?
        for attempt in 1...retryPolicy.maxAttempts {
            if let delay = retryPolicy.backoffBeforeAttempt(attempt) {
                await retrySleep(delay)
            }

            do {
                let result = try await executor.execute(
                    command: command,
                    args: args,
                    cwd: nil,
                    environment: ["ZMX_DIR": zmxDir]
                )
                guard result.succeeded else {
                    let error = SessionBackendError.operationFailed(
                        "\(operation) failed (attempt \(attempt)/\(retryPolicy.maxAttempts)): \(result.stderr)"
                    )
                    lastError = error
                    if attempt < retryPolicy.maxAttempts {
                        zmxLogger.debug(
                            "\(operation) failed on attempt \(attempt)/\(self.retryPolicy.maxAttempts); retrying"
                        )
                        continue
                    }
                    throw error
                }
                return result
            } catch {
                lastError = error
                if attempt < retryPolicy.maxAttempts {
                    zmxLogger.debug(
                        "\(operation) threw on attempt \(attempt)/\(self.retryPolicy.maxAttempts): \(error.localizedDescription)"
                    )
                    continue
                }
                throw error
            }
        }

        throw lastError ?? SessionBackendError.timeout
    }

    private static func getDefaultShell() -> String {
        SessionConfiguration.defaultShell()
    }
}
