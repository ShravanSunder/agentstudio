import Foundation

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

    init(executor: ProcessExecutor = DefaultProcessExecutor(), ghostConfigPath: String) {
        self.executor = executor
        self.ghostConfigPath = ghostConfigPath
    }

    // MARK: - Session ID Generation

    /// Generate a deterministic session ID for a project+worktree pair.
    /// Format: `agentstudio--<project8>--<worktree8>`
    static func sessionId(projectId: UUID, worktreeId: UUID) -> String {
        let projectPrefix = projectId.uuidString.prefix(8).lowercased()
        let worktreePrefix = worktreeId.uuidString.prefix(8).lowercased()
        return "\(sessionPrefix)\(projectPrefix)--\(worktreePrefix)"
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
                return false
            }
        }
    }

    // MARK: - Pane Session Lifecycle

    func createPaneSession(projectId: UUID, worktree: Worktree) async throws -> PaneSessionHandle {
        let sessionId = Self.sessionId(projectId: projectId, worktreeId: worktree.id)

        let result = try await executor.execute(
            command: "tmux",
            args: [
                "-L", Self.socketName,
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
            projectId: projectId,
            worktreeId: worktree.id,
            displayName: worktree.name,
            workingDirectory: worktree.path
        )
    }

    func attachCommand(for handle: PaneSessionHandle) -> String {
        "tmux -L \(Self.socketName) -f \(ghostConfigPath) new-session -A -s \(handle.id) -c \(handle.workingDirectory.path)"
    }

    func destroyPaneSession(_ handle: PaneSessionHandle) async throws {
        let result = try await executor.execute(
            command: "tmux",
            args: ["-L", Self.socketName, "kill-session", "-t", handle.id],
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
                args: ["-L", Self.socketName, "has-session", "-t", handle.id],
                cwd: nil,
                environment: nil
            )
            return result.succeeded
        } catch {
            return false
        }
    }

    // MARK: - Discovery

    func socketExists() -> Bool {
        let uid = getuid()
        let socketDir = ProcessInfo.processInfo.environment["TMUX_TMPDIR"]
            ?? "/tmp/tmux-\(uid)"
        return FileManager.default.fileExists(atPath: socketDir + "/\(Self.socketName)")
    }

    func sessionExists(_ handle: PaneSessionHandle) async -> Bool {
        await healthCheck(handle)
    }

    func discoverOrphanSessions(excluding knownIds: Set<String>) async -> [String] {
        do {
            let result = try await executor.execute(
                command: "tmux",
                args: ["-L", Self.socketName, "list-sessions", "-F", "#{session_name}"],
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
            return []
        }
    }

    func destroySessionById(_ sessionId: String) async throws {
        let result = try await executor.execute(
            command: "tmux",
            args: ["-L", Self.socketName, "kill-session", "-t", sessionId],
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
