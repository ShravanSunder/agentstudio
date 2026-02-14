import Foundation
import os

private let tmuxLogger = Logger(subsystem: "com.agentstudio", category: "TmuxBackend")

// MARK: - Legacy Backend Types (contained here until Phase 4 wires SessionRuntime → TmuxBackend)

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

// MARK: - TmuxBackend

/// tmux-based implementation of SessionBackend.
/// Creates one isolated tmux session per terminal pane on a custom socket (`-L agentstudio`),
/// completely invisible to the user's own tmux.
final class TmuxBackend: SessionBackend {
    /// Prefix for all Agent Studio tmux sessions.
    static let sessionPrefix = "agentstudio--"

    /// Custom socket name — isolates ghost tmux from user's default server.
    static let socketName = "agentstudio"

    private let executor: ProcessExecutor
    private let ghostConfigPath: String
    private let socket: String
    private let terminfoDir: String?

    init(executor: ProcessExecutor = DefaultProcessExecutor(), ghostConfigPath: String, socketName: String = TmuxBackend.socketName, terminfoDir: String? = nil) {
        self.executor = executor
        self.ghostConfigPath = ghostConfigPath
        self.socket = socketName
        self.terminfoDir = terminfoDir
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
            do {
                let result = try await executor.execute(
                    command: "tmux",
                    args: ["-V"],
                    cwd: nil,
                    environment: nil
                )
                return result.succeeded
            } catch {
                tmuxLogger.debug("tmux availability check failed: \(error.localizedDescription)")
                return false
            }
        }
    }

    // MARK: - Pane Session Lifecycle

    func createPaneSession(repo: Repo, worktree: Worktree, paneId: UUID) async throws -> PaneSessionHandle {
        let sessionId = Self.sessionId(repoStableKey: repo.stableKey, worktreeStableKey: worktree.stableKey, paneId: paneId)

        let result = try await executor.execute(
            command: "tmux",
            args: [
                "-L", socket,
                "-f", ghostConfigPath,
                "new-session",
                "-d",
                "-s", sessionId,
                "-c", worktree.path.path,
            ],
            cwd: nil,
            environment: nil
        )

        guard result.succeeded else {
            throw SessionBackendError.operationFailed(
                "Failed to create tmux session '\(sessionId)': \(result.stderr)"
            )
        }

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
            tmuxBin: "tmux",
            socketName: socket,
            ghostConfigPath: ghostConfigPath,
            sessionId: handle.id,
            workingDirectory: handle.workingDirectory.path,
            terminfoDir: terminfoDir
        )
    }

    /// Build the tmux attach command with runtime hardening applied.
    /// The hardening is repeated at attach-time to correct stale tmux servers
    /// that may have been started before updated ghost.conf options existed.
    ///
    /// The `terminfoDir` parameter injects our custom terminfo directory into
    /// the tmux server's global environment via `set-environment -g TERMINFO`.
    /// This is critical because the tmux server persists across app restarts and
    /// may have been started with a stale TERMINFO pointing to an installed
    /// Ghostty.app or system path, causing programs inside tmux to find the
    /// system xterm-256color (X10 mouse, no RGB) instead of our custom one
    /// (SGR mouse, full Ghostty capabilities).
    static func buildAttachCommand(
        tmuxBin: String,
        socketName: String,
        ghostConfigPath: String,
        sessionId: String,
        workingDirectory: String,
        terminfoDir: String? = nil
    ) -> String {
        let config = shellEscape(ghostConfigPath)
        let cwd = shellEscape(workingDirectory)
        let escapedSessionId = shellEscape(sessionId)
        var cmd = "\(tmuxBin) -L \(socketName) -f \(config) new-session -A -s \(escapedSessionId) -c \(cwd)"
        cmd += " \\; set-option -g mouse off"
        // Broad unbinding at attach time corrects stale tmux servers started before
        // ghost.conf had individual unbinds. ghost.conf itself uses per-event unbinds
        // (not `unbind -a`) to avoid destroying key tables at config-load time.
        cmd += " \\; unbind-key -a"
        cmd += " \\; unbind-key -a -T root"
        cmd += " \\; unbind-key -a -T copy-mode"
        cmd += " \\; unbind-key -a -T copy-mode-vi"
        if let terminfoDir {
            cmd += " \\; set-environment -g TERMINFO \(shellEscape(terminfoDir))"
        }
        return cmd
    }

    /// Single-quote a string for safe shell interpolation.
    static func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func destroyPaneSession(_ handle: PaneSessionHandle) async throws {
        let result = try await executor.execute(
            command: "tmux",
            args: ["-L", socket, "kill-session", "-t", handle.id],
            cwd: nil,
            environment: nil
        )

        guard result.succeeded else {
            throw SessionBackendError.operationFailed(
                "Failed to destroy session '\(handle.id)': \(result.stderr)"
            )
        }
    }

    func healthCheck(_ handle: PaneSessionHandle) async -> Bool {
        do {
            let result = try await executor.execute(
                command: "tmux",
                args: ["-L", socket, "has-session", "-t", handle.id],
                cwd: nil,
                environment: nil
            )
            return result.succeeded
        } catch {
            tmuxLogger.debug("Health check failed for session \(handle.id): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Discovery

    func socketExists() -> Bool {
        let uid = getuid()
        let socketDir = ProcessInfo.processInfo.environment["TMUX_TMPDIR"]
            ?? "/tmp/tmux-\(uid)"
        return FileManager.default.fileExists(atPath: socketDir + "/\(socket)")
    }

    func sessionExists(_ handle: PaneSessionHandle) async -> Bool {
        await healthCheck(handle)
    }

    func discoverOrphanSessions(excluding knownIds: Set<String>) async -> [String] {
        do {
            let result = try await executor.execute(
                command: "tmux",
                args: ["-L", socket, "list-sessions", "-F", "#{session_name}"],
                cwd: nil,
                environment: nil
            )

            guard result.succeeded else { return [] }

            return result.stdout
                .components(separatedBy: "\n")
                .filter { !$0.isEmpty }
                .filter { $0.hasPrefix(Self.sessionPrefix) }
                .filter { !knownIds.contains($0) }
        } catch {
            tmuxLogger.warning("Failed to discover orphan sessions: \(error.localizedDescription)")
            return []
        }
    }

    func destroySessionById(_ sessionId: String) async throws {
        let result = try await executor.execute(
            command: "tmux",
            args: ["-L", socket, "kill-session", "-t", sessionId],
            cwd: nil,
            environment: nil
        )

        guard result.succeeded else {
            throw SessionBackendError.operationFailed(
                "Failed to destroy session '\(sessionId)': \(result.stderr)"
            )
        }
    }
}
