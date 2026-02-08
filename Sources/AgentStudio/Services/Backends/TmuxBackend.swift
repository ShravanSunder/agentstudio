import Foundation
import os

private let tmuxLogger = Logger(subsystem: "com.agentstudio", category: "TmuxBackend")

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

    init(executor: ProcessExecutor = DefaultProcessExecutor(), ghostConfigPath: String, socketName: String = TmuxBackend.socketName) {
        self.executor = executor
        self.ghostConfigPath = ghostConfigPath
        self.socket = socketName
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
                "-d",                           // detached (headless)
                "-s", sessionId,                 // session name
                "-c", worktree.path.path,        // working directory
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
        let config = Self.shellEscape(ghostConfigPath)
        let cwd = Self.shellEscape(handle.workingDirectory.path)
        let sessionId = Self.shellEscape(handle.id)
        return "tmux -L \(socket) -f \(config) new-session -A -s \(sessionId) -c \(cwd)"
    }

    /// Single-quote a string for safe shell interpolation.
    private static func shellEscape(_ path: String) -> String {
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
