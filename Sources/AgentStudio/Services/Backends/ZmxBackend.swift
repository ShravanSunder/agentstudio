import Foundation
import os

private let zmxLogger = Logger(subsystem: "com.agentstudio", category: "ZmxBackend")

// MARK: - Backend Types

/// Identifies a backend session that backs a single terminal pane.
struct PaneSessionHandle: Equatable, Sendable, Codable, Hashable {
    let id: String
    let paneId: UUID
    let projectId: UUID
    let worktreeId: UUID
    let repoPath: URL
    let worktreePath: URL
    let displayName: String
    let workingDirectory: URL

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

/// Backend-agnostic protocol for managing per-pane terminal sessions.
protocol SessionBackend: Sendable {
    var isAvailable: Bool { get async }
    func createPaneSession(repo: Repo, worktree: Worktree, paneId: UUID) async throws -> PaneSessionHandle
    func attachCommand(for handle: PaneSessionHandle) -> String
    func destroyPaneSession(_ handle: PaneSessionHandle) async throws
    func healthCheck(_ handle: PaneSessionHandle) async -> Bool
    func socketExists() -> Bool
    func sessionExists(_ handle: PaneSessionHandle) async -> Bool
    func discoverOrphanSessions(excluding knownIds: Set<String>) async -> [String]
    func destroySessionById(_ sessionId: String) async throws
}

enum SessionBackendError: Error, LocalizedError {
    case notAvailable
    case timeout
    case operationFailed(String)
    case sessionNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Session backend (zmx) is not available"
        case .timeout:
            return "Operation timed out"
        case .operationFailed(let detail):
            return "Operation failed: \(detail)"
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        }
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
    /// Prefix for all Agent Studio zmx sessions.
    static let sessionPrefix = "agentstudio--"

    /// Default zmx directory for socket/state isolation.
    static let defaultZmxDir: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agentstudio/zmx").path
    }()

    private let executor: ProcessExecutor
    private let zmxPath: String
    private let zmxDir: String

    init(
        executor: ProcessExecutor = DefaultProcessExecutor(),
        zmxPath: String,
        zmxDir: String = ZmxBackend.defaultZmxDir
    ) {
        self.executor = executor
        self.zmxPath = zmxPath
        self.zmxDir = zmxDir
    }

    // MARK: - Session ID Generation

    /// Generate a deterministic session ID from stable keys + pane UUID.
    /// Format: `agentstudio--<repoKey16>--<wtKey16>--<pane16>` (65 chars)
    static func sessionId(repoStableKey: String, worktreeStableKey: String, paneId: UUID) -> String {
        let panePrefix = String(paneId.uuidString.replacingOccurrences(of: "-", with: "").prefix(16)).lowercased()
        return "\(sessionPrefix)\(repoStableKey)--\(worktreeStableKey)--\(panePrefix)"
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
    func createPaneSession(repo: Repo, worktree: Worktree, paneId: UUID) async throws -> PaneSessionHandle {
        let sessionId = Self.sessionId(
            repoStableKey: repo.stableKey,
            worktreeStableKey: worktree.stableKey,
            paneId: paneId
        )

        // Ensure the zmx directory exists for socket isolation
        try FileManager.default.createDirectory(
            atPath: zmxDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        return PaneSessionHandle(
            id: sessionId,
            paneId: paneId,
            projectId: repo.id,
            worktreeId: worktree.id,
            repoPath: repo.repoPath,
            worktreePath: worktree.path,
            displayName: worktree.name,
            workingDirectory: worktree.path
        )
    }

    func attachCommand(for handle: PaneSessionHandle) -> String {
        Self.buildAttachCommand(
            zmxPath: zmxPath,
            zmxDir: zmxDir,
            sessionId: handle.id,
            shell: Self.getDefaultShell()
        )
    }

    /// Build the zmx attach command.
    ///
    /// Format: `/usr/bin/env ZMX_DIR=<dir> <zmxPath> attach <sessionId> <shell> -i -l`
    ///
    /// Uses `/usr/bin/env` to set ZMX_DIR because macOS Ghostty wraps commands
    /// through `login(1)` which may interfere with inline `VAR=val cmd` syntax.
    /// zmx auto-creates a daemon on first attach — no separate create step needed.
    static func buildAttachCommand(
        zmxPath: String,
        zmxDir: String,
        sessionId: String,
        shell: String
    ) -> String {
        let escapedDir = shellEscape(zmxDir)
        let escapedPath = shellEscape(zmxPath)
        let escapedId = shellEscape(sessionId)
        let escapedShell = shellEscape(shell)
        return "/usr/bin/env ZMX_DIR=\(escapedDir) \(escapedPath) attach \(escapedId) \(escapedShell) -i -l"
    }

    /// Single-quote a string for safe shell interpolation.
    static func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func destroyPaneSession(_ handle: PaneSessionHandle) async throws {
        let result = try await executor.execute(
            command: zmxPath,
            args: ["kill", handle.id],
            cwd: nil,
            environment: ["ZMX_DIR": zmxDir]
        )

        guard result.succeeded else {
            throw SessionBackendError.operationFailed(
                "Failed to destroy zmx session '\(handle.id)': \(result.stderr)"
            )
        }
    }

    /// Check if a zmx session is alive by parsing `zmx list` output.
    /// Uses conservative substring matching since the output format
    /// is not yet fully stabilized.
    func healthCheck(_ handle: PaneSessionHandle) async -> Bool {
        do {
            let result = try await executor.execute(
                command: zmxPath,
                args: ["list"],
                cwd: nil,
                environment: ["ZMX_DIR": zmxDir]
            )
            guard result.succeeded else { return false }
            let lines = result.stdout.components(separatedBy: "\n")
            let found = lines.contains { $0.contains(handle.id) }
            if !found, !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                zmxLogger.debug("zmx list succeeded but session \(handle.id) not found in output")
            }
            return found
        } catch {
            zmxLogger.debug("Health check failed for session \(handle.id): \(error.localizedDescription)")
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

    /// Discover zmx sessions that are not tracked by the store.
    /// Filters by the `agentstudio--` prefix to only find our sessions.
    func discoverOrphanSessions(excluding knownIds: Set<String>) async -> [String] {
        do {
            let result = try await executor.execute(
                command: zmxPath,
                args: ["list"],
                cwd: nil,
                environment: ["ZMX_DIR": zmxDir]
            )

            guard result.succeeded else { return [] }

            // Parse zmx list output — each line may contain a session name.
            // Extract session names that start with our prefix.
            return result.stdout
                .components(separatedBy: "\n")
                .filter { !$0.isEmpty }
                .compactMap { line -> String? in
                    // zmx list output is tab-delimited. Extract the field containing our prefix,
                    // then isolate the session name (from prefix to next tab or end of field).
                    guard let range = line.range(of: Self.sessionPrefix) else { return nil }
                    let fromPrefix = line[range.lowerBound...]
                    return fromPrefix.split(separator: "\t").first.map(String.init)
                }
                .filter { $0.hasPrefix(Self.sessionPrefix) }
                .filter { !knownIds.contains($0) }
        } catch {
            zmxLogger.warning("Failed to discover orphan sessions: \(error.localizedDescription)")
            return []
        }
    }

    func destroySessionById(_ sessionId: String) async throws {
        let result = try await executor.execute(
            command: zmxPath,
            args: ["kill", sessionId],
            cwd: nil,
            environment: ["ZMX_DIR": zmxDir]
        )

        guard result.succeeded else {
            throw SessionBackendError.operationFailed(
                "Failed to destroy zmx session '\(sessionId)': \(result.stderr)"
            )
        }
    }

    // MARK: - Helpers

    private static func getDefaultShell() -> String {
        SessionConfiguration.defaultShell()
    }
}
