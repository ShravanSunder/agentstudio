import Foundation

// MARK: - Handle Types

/// Identifies a backend session that backs a single terminal pane.
/// Each terminal pane (worktree) gets its own isolated session.
struct PaneSessionHandle: Equatable, Sendable, Codable, Hashable {
    /// Backend session identifier, e.g. `agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--a1b2c3d4e5f6a7b8`
    let id: String
    let paneId: UUID
    let projectId: UUID
    let worktreeId: UUID
    let repoPath: URL
    let worktreePath: URL
    let displayName: String
    let workingDirectory: URL

    /// Whether the id matches the v3 session ID format.
    /// Format: `agentstudio--<repo16hex>--<wt16hex>--<pane16hex>` (65 chars)
    var hasValidId: Bool {
        guard id.hasPrefix("agentstudio--") else { return false }
        let suffix = String(id.dropFirst(13))
        let segments = suffix.components(separatedBy: "--")
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        guard segments.count == 3,
              segments.allSatisfy({ $0.count == 16 }) else { return false }
        return segments.allSatisfy { seg in
            seg.unicodeScalars.allSatisfy { hexChars.contains($0) }
        }
    }
}

// MARK: - SessionBackend Protocol

/// Backend-agnostic protocol for managing per-pane terminal sessions.
/// Each terminal pane gets its own isolated session.
protocol SessionBackend: Sendable {

    /// Whether the backend binary (tmux) is available on the system.
    var isAvailable: Bool { get async }

    // MARK: Pane Session Lifecycle

    /// Create a new background session for the given repo, worktree, and pane.
    func createPaneSession(repo: Repo, worktree: Worktree, paneId: UUID) async throws -> PaneSessionHandle

    /// Returns the shell command to attach to a pane session.
    func attachCommand(for handle: PaneSessionHandle) -> String

    /// Destroy a pane session.
    func destroyPaneSession(_ handle: PaneSessionHandle) async throws

    /// Fast health check — returns true if the session is alive.
    func healthCheck(_ handle: PaneSessionHandle) async -> Bool

    // MARK: Discovery

    /// Check if the backend socket/server is running.
    func socketExists() -> Bool

    /// Check if a specific session exists.
    func sessionExists(_ handle: PaneSessionHandle) async -> Bool

    /// Find orphan sessions (agentstudio-prefixed) not tracked by the registry.
    func discoverOrphanSessions(excluding knownIds: Set<String>) async -> [String]

    /// Destroy a session by its ID string (for orphan cleanup).
    func destroySessionById(_ sessionId: String) async throws
}

// MARK: - SessionBackendError

enum SessionBackendError: Error, LocalizedError {
    case notAvailable
    case timeout
    case operationFailed(String)
    case sessionNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Session backend (tmux) is not installed"
        case .timeout:
            return "Operation timed out"
        case .operationFailed(let detail):
            return "Operation failed: \(detail)"
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        }
    }
}

// MARK: - ProcessExecutor Protocol

/// Testable wrapper for CLI execution. In production, runs Process.
/// In tests, returns canned responses.
protocol ProcessExecutor: Sendable {
    func execute(
        command: String,
        args: [String],
        cwd: URL?,
        environment: [String: String]?
    ) async throws -> ProcessResult
}

/// Result of a CLI command execution.
struct ProcessResult: Sendable {
    let exitCode: Int
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

// MARK: - DefaultProcessExecutor

/// Production executor that spawns real processes.
struct DefaultProcessExecutor: ProcessExecutor {
    func execute(
        command: String,
        args: [String],
        cwd: URL?,
        environment: [String: String]?
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args

        if let cwd {
            process.currentDirectoryURL = cwd
        }

        // Merge provided environment with inherited, ensuring brew paths
        var env = ProcessInfo.processInfo.environment
        if let override = environment {
            env.merge(override) { _, new in new }
        }
        if let path = env["PATH"] {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(path)"
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Read pipes FIRST to prevent buffer deadlock.
        // If the child fills the pipe buffer (~64KB), it blocks on write.
        // Reading first drains the buffer so the child can proceed to exit.
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        // Safe to call waitUntilExit() now — pipes are fully drained so no
        // deadlock is possible. For short-lived commands (tmux), the process
        // has already exited by the time readDataToEndOfFile() returns EOF.
        process.waitUntilExit()

        return ProcessResult(
            exitCode: Int(process.terminationStatus),
            stdout: String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            stderr: String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }
}
