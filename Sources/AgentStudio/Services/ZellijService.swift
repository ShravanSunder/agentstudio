import Foundation
import os

private let logger = Logger(subsystem: "com.agentstudio", category: "Zellij")

/// Error types for Zellij operations
enum ZellijError: Error, LocalizedError {
    case notInstalled
    case sessionCreationFailed(String)
    case sessionNotFound(String)
    case tabCreationFailed(String)
    case commandFailed(command: String, stderr: String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Zellij is not installed. Install with: brew install zellij"
        case .sessionCreationFailed(let msg):
            return "Failed to create Zellij session: \(msg)"
        case .sessionNotFound(let name):
            return "Zellij session not found: \(name)"
        case .tabCreationFailed(let msg):
            return "Failed to create tab: \(msg)"
        case .commandFailed(let cmd, let stderr):
            return "Zellij command failed (\(cmd)): \(stderr)"
        }
    }
}

/// Manages Zellij sessions via CLI
@MainActor
final class ZellijService: ObservableObject {
    static let shared = ZellijService()

    /// Active sessions managed by Agent Studio
    @Published private(set) var sessions: [ZellijSession] = []

    /// Path to invisible.kdl config
    let configPath: URL

    /// Path to minimal.kdl layout
    let layoutPath: URL

    /// Process executor (injectable for testing)
    private let executor: ProcessExecutor

    /// Zellij binary path
    private let zellijPath: String

    // MARK: - Initialization

    /// Production singleton init
    private init() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".agentstudio/zellij")
        self.configPath = appSupport.appending(path: "invisible.kdl")
        self.layoutPath = appSupport.appending(path: "layouts/minimal.kdl")
        self.executor = RealProcessExecutor()
        self.zellijPath = "/opt/homebrew/bin/zellij"
    }

    /// Test init with injected dependencies
    init(executor: ProcessExecutor, configPath: URL? = nil, layoutPath: URL? = nil) {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".agentstudio/zellij")
        self.configPath = configPath ?? appSupport.appending(path: "invisible.kdl")
        self.layoutPath = layoutPath ?? appSupport.appending(path: "layouts/minimal.kdl")
        self.executor = executor
        self.zellijPath = "/opt/homebrew/bin/zellij"
    }

    // MARK: - Setup

    /// Ensure config files exist (call on app launch)
    func ensureConfigFiles() throws {
        let configDir = configPath.deletingLastPathComponent()
        let layoutDir = layoutPath.deletingLastPathComponent()

        try FileManager.default.createDirectory(at: layoutDir, withIntermediateDirectories: true)

        // Write invisible.kdl if not exists
        if !FileManager.default.fileExists(atPath: configPath.path) {
            try Self.invisibleKdl.write(to: configPath, atomically: true, encoding: .utf8)
            logger.info("Created Zellij config at \(self.configPath.path)")
        }

        // Write minimal.kdl if not exists
        if !FileManager.default.fileExists(atPath: layoutPath.path) {
            try Self.minimalKdl.write(to: layoutPath, atomically: true, encoding: .utf8)
            logger.info("Created Zellij layout at \(self.layoutPath.path)")
        }

        logger.info("Zellij config files ready")
    }

    /// Check if Zellij is installed
    func isZellijInstalled() async -> Bool {
        let result = await executor.execute("/usr/bin/which", arguments: ["zellij"])
        return result.succeeded
    }

    // MARK: - Session Lifecycle

    /// Create a new session for a project
    func createSession(for project: Project) async throws -> ZellijSession {
        let sessionId = ZellijSession.sessionId(for: project.id)

        // Check if already exists
        if await sessionExists(sessionId) {
            logger.info("Session \(sessionId) already exists, reusing")
            if let existing = sessions.first(where: { $0.id == sessionId }) {
                return existing
            }
            // Session exists in Zellij but not in our array - add it
            let session = ZellijSession(
                id: sessionId,
                projectId: project.id,
                displayName: project.name
            )
            sessions.append(session)
            return session
        }

        // Create background session with invisible config
        let result = await executor.execute(zellijPath, arguments: [
            "--config", configPath.path,
            "--layout", layoutPath.path,
            "attach", sessionId,
            "--create-background"
        ])

        if !result.succeeded && !result.stderr.contains("already exists") {
            throw ZellijError.sessionCreationFailed(result.stderr)
        }

        let session = ZellijSession(
            id: sessionId,
            projectId: project.id,
            displayName: project.name
        )

        sessions.append(session)
        logger.info("Created Zellij session: \(sessionId)")

        return session
    }

    /// Destroy a session
    func destroySession(_ session: ZellijSession) async throws {
        let result = await executor.execute(zellijPath, arguments: [
            "kill-session", session.id
        ])

        if !result.succeeded && !result.stderr.contains("not found") {
            throw ZellijError.commandFailed(command: "kill-session", stderr: result.stderr)
        }

        sessions.removeAll { $0.id == session.id }
        logger.info("Destroyed Zellij session: \(session.id)")
    }

    /// Check if session exists in Zellij
    func sessionExists(_ sessionId: String) async -> Bool {
        let result = await executor.execute(zellijPath, arguments: ["list-sessions"])
        return result.stdout.contains(sessionId)
    }

    /// Discover all Agent Studio managed sessions
    func discoverSessions() async -> [String] {
        let result = await executor.execute(zellijPath, arguments: ["list-sessions"])

        return result.stdout
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                // Strip ANSI color codes and extract session name
                let cleaned = line.replacingOccurrences(
                    of: "\\x1B\\[[0-9;]*m",
                    with: "",
                    options: .regularExpression
                )
                let name = cleaned.components(separatedBy: .whitespaces).first ?? ""
                return name.hasPrefix("agentstudio--") ? name : nil
            }
    }

    // MARK: - Tab Management

    /// Create a tab for a worktree
    func createTab(in session: ZellijSession, for worktree: Worktree) async throws -> ZellijTab {
        // Check if tab already exists
        if let existingTab = session.tabs.first(where: { $0.worktreeId == worktree.id }) {
            return existingTab
        }

        let result = await executor.execute(zellijPath, arguments: [
            "--session", session.id,
            "action", "new-tab",
            "--name", worktree.branch,
            "--cwd", worktree.path.path
        ])

        if !result.succeeded {
            throw ZellijError.tabCreationFailed(result.stderr)
        }

        // Get tab count to determine new tab's index
        let tabNames = try await getTabNames(for: session)
        let tabIndex = tabNames.count

        let tab = ZellijTab(
            id: tabIndex,
            name: worktree.branch,
            worktreeId: worktree.id,
            workingDirectory: worktree.path
        )

        // Update session in our array
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx].tabs.append(tab)
        }

        logger.info("Created tab '\(worktree.branch)' in session \(session.id)")
        return tab
    }

    /// Close a tab
    func closeTab(_ tab: ZellijTab, in session: ZellijSession) async throws {
        // Switch to tab first, then close
        _ = await executor.execute(zellijPath, arguments: [
            "--session", session.id,
            "action", "go-to-tab", String(tab.id)
        ])

        let result = await executor.execute(zellijPath, arguments: [
            "--session", session.id,
            "action", "close-tab"
        ])

        if !result.succeeded {
            throw ZellijError.commandFailed(command: "close-tab", stderr: result.stderr)
        }

        // Update session in our array
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx].tabs.removeAll { $0.id == tab.id }
        }

        logger.info("Closed tab \(tab.id) in session \(session.id)")
    }

    /// Get tab names for a session
    func getTabNames(for session: ZellijSession) async throws -> [String] {
        let result = await executor.execute(zellijPath, arguments: [
            "--session", session.id,
            "action", "query-tab-names"
        ])

        return result.stdout
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
    }

    // MARK: - Commands

    /// Get the command string for Ghostty to attach to a session
    func attachCommand(for session: ZellijSession) -> String {
        "\(zellijPath) --config \(configPath.path) attach \(session.id)"
    }

    /// Send text to the focused pane in a session
    func sendText(_ text: String, to session: ZellijSession) async throws {
        let result = await executor.execute(zellijPath, arguments: [
            "--session", session.id,
            "action", "write-chars", text
        ])

        if !result.succeeded {
            throw ZellijError.commandFailed(command: "write-chars", stderr: result.stderr)
        }
    }

    // MARK: - Session Lookup

    /// Find session for a project
    func session(for project: Project) -> ZellijSession? {
        let expectedId = ZellijSession.sessionId(for: project.id)
        return sessions.first { $0.id == expectedId }
    }

    /// Find session containing a specific tab
    func session(containing tab: ZellijTab) -> ZellijSession? {
        sessions.first { session in
            session.tabs.contains { $0.id == tab.id && $0.worktreeId == tab.worktreeId }
        }
    }

    // MARK: - Default Configs

    private static let invisibleKdl = """
    // Agent Studio: Invisible Zellij Configuration
    // All keys pass through, no visible UI chrome

    default_mode "locked"
    keybinds clear-defaults=true { }
    pane_frames false
    simplified_ui true
    show_startup_tips false
    show_release_notes false
    session_serialization true
    serialize_pane_viewport true
    scrollback_lines_to_serialize 10000
    mouse_mode false
    scroll_buffer_size 50000
    """

    private static let minimalKdl = """
    // Minimal layout - single pane, no bars
    layout {
        pane
    }
    """
}
