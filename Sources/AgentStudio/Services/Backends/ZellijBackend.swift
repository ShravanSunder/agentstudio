// ZellijBackend.swift
// AgentStudio
//
// Zellij-based session backend with full session and tab management.

import Foundation
import OSLog

/// Zellij-based session backend with full features.
final class ZellijBackend: SessionBackend, @unchecked Sendable {

    // MARK: - Properties

    private let config: SessionConfiguration
    private let executor: ProcessExecutor
    private let logger = Logger(subsystem: "AgentStudio", category: "ZellijBackend")

    // Paths
    private var zellijPath: String { config.zellijPath }
    private var socketDir: URL { config.socketDir }
    private let configPath: URL
    private let layoutPath: URL

    // MARK: - Timeout Constants

    /// Timeout for quick operations (list-sessions, query-tab-names)
    private static let listTimeout: TimeInterval = 5.0

    /// Timeout for session creation/destruction
    private static let sessionTimeout: TimeInterval = 10.0

    /// Timeout for tab operations
    private static let tabTimeout: TimeInterval = 10.0

    /// Timeout for IPC health checks
    private static let healthCheckTimeout: TimeInterval = 2.0

    // MARK: - Initialization

    @MainActor
    init(executor: ProcessExecutor = RealProcessExecutor()) {
        self.config = SessionConfiguration.shared
        self.executor = executor

        // Setup config paths
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".agentstudio/zellij")
        self.configPath = appSupport.appending(path: "invisible.kdl")
        self.layoutPath = appSupport.appending(path: "layouts/minimal.kdl")
    }

    /// Test init with custom paths
    init(executor: ProcessExecutor, configPath: URL, layoutPath: URL, config: SessionConfiguration) {
        self.config = config
        self.executor = executor
        self.configPath = configPath
        self.layoutPath = layoutPath
    }

    // MARK: - Availability

    var isAvailable: Bool {
        get async {
            await MainActor.run { config.zellijAvailable }
        }
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

    // MARK: - Fast Socket Check (no process spawn)

    /// Check if a session socket exists (fast filesystem check).
    func socketExists(_ sessionId: String) -> Bool {
        let socketPath = socketDir.appendingPathComponent("\(sessionId)=")

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: socketPath.path, isDirectory: &isDirectory) else {
            return false
        }

        // Verify it's actually a socket
        var statInfo = stat()
        guard stat(socketPath.path, &statInfo) == 0 else {
            return false
        }

        let isSocket = (statInfo.st_mode & S_IFMT) == S_IFSOCK
        logger.debug("Socket check for \(sessionId): exists=\(isSocket)")
        return isSocket
    }

    /// Discover orphan sessions (sockets not in our registry).
    func discoverOrphanSessions(excluding known: Set<String>) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: socketDir.path) else {
            logger.debug("Cannot read socket directory: \(self.socketDir.path)")
            return []
        }

        let orphans = contents.compactMap { filename -> String? in
            // Zellij socket files end with "="
            guard filename.hasPrefix("agentstudio--"),
                  filename.hasSuffix("=") else {
                return nil
            }
            let sessionId = String(filename.dropLast()) // Remove trailing "="
            return known.contains(sessionId) ? nil : sessionId
        }

        if !orphans.isEmpty {
            logger.info("Discovered \(orphans.count) orphan session(s)")
        }

        return orphans
    }

    // MARK: - Session Lifecycle

    func createSession(for project: Project) async throws -> SessionHandle {
        let sessionId = SessionHandle.sessionId(for: project.id)

        // Ensure config files exist
        try ensureConfigFiles()

        // Use --create-background (idempotent: creates if missing, attaches if exists)
        let result = await executor.execute(zellijPath, arguments: [
            "--config", configPath.path,
            "--layout", layoutPath.path,
            "attach", sessionId,
            "--create-background"
        ], timeout: Self.sessionTimeout)

        if result.timedOut {
            throw SessionBackendError.timeout(operation: "createSession(\(sessionId))")
        }

        // Both success and "already exists" are acceptable
        let stderr = result.stderr.lowercased()
        if !result.succeeded &&
           !stderr.contains("already exists") &&
           !stderr.contains("attaching") &&
           !stderr.contains("created") {
            throw SessionBackendError.operationFailed(
                operation: "createSession",
                reason: result.stderr
            )
        }

        logger.info("Created/attached session: \(sessionId)")

        return SessionHandle(
            id: sessionId,
            projectId: project.id,
            displayName: project.name
        )
    }

    func attachCommand(for handle: SessionHandle, tab: TabHandle?) -> String {
        // Note: Zellij doesn't support attaching to a specific tab via CLI
        // Tab switching would need to happen after attach via action commands
        return "\(zellijPath) --config \(configPath.path) attach \(handle.id)"
    }

    func destroySession(_ handle: SessionHandle) async throws {
        let result = await executor.execute(zellijPath, arguments: [
            "kill-session", handle.id
        ], timeout: Self.sessionTimeout)

        if result.timedOut {
            throw SessionBackendError.timeout(operation: "destroySession(\(handle.id))")
        }

        // "not found" is acceptable (idempotent)
        if !result.succeeded && !result.stderr.lowercased().contains("not found") {
            throw SessionBackendError.operationFailed(
                operation: "destroySession",
                reason: result.stderr
            )
        }

        logger.info("Destroyed session: \(handle.id)")
    }

    func healthCheck(_ handle: SessionHandle) async -> Bool {
        // Fast path: check socket exists
        guard socketExists(handle.id) else {
            logger.debug("Health check failed for \(handle.id): socket not found")
            return false
        }

        // Verify socket is responsive (try a quick query)
        let result = await executor.execute(zellijPath, arguments: [
            "--session", handle.id,
            "action", "query-tab-names"
        ], timeout: Self.healthCheckTimeout)

        let isHealthy = !result.timedOut && result.succeeded
        logger.debug("Health check for \(handle.id): \(isHealthy ? "passed" : "failed")")
        return isHealthy
    }

    // MARK: - Tab Lifecycle

    func createTab(in session: SessionHandle, for worktree: Worktree) async throws -> TabHandle {
        let result = await executor.execute(zellijPath, arguments: [
            "--session", session.id,
            "action", "new-tab",
            "--name", worktree.branch,
            "--cwd", worktree.path.path
        ], timeout: Self.tabTimeout)

        if result.timedOut {
            throw SessionBackendError.timeout(operation: "createTab(\(worktree.branch))")
        }

        if !result.succeeded {
            throw SessionBackendError.operationFailed(
                operation: "createTab",
                reason: result.stderr
            )
        }

        // Get tab ID by querying tab names (new tab is last)
        let tabNames = try await getTabNames(session)
        let tabId = tabNames.count

        logger.info("Created tab '\(worktree.branch)' (id: \(tabId)) in session \(session.id)")

        return TabHandle(
            id: tabId,
            sessionId: session.id,
            worktreeId: worktree.id,
            name: worktree.branch,
            workingDirectory: worktree.path
        )
    }

    func getTabNames(_ session: SessionHandle) async throws -> [String] {
        let result = await executor.execute(zellijPath, arguments: [
            "--session", session.id,
            "action", "query-tab-names"
        ], timeout: Self.listTimeout)

        if result.timedOut {
            throw SessionBackendError.timeout(operation: "getTabNames(\(session.id))")
        }

        // Note: query-tab-names may fail if session is not attached
        // This is a known Zellij limitation for background sessions
        if !result.succeeded {
            logger.warning("query-tab-names failed for \(session.id): \(result.stderr)")
            // Return empty instead of throwing - caller should handle gracefully
            return []
        }

        return result.stdout
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
    }

    func closeTab(_ tab: TabHandle) async throws {
        // Switch to tab first, then close
        let goToResult = await executor.execute(zellijPath, arguments: [
            "--session", tab.sessionId,
            "action", "go-to-tab", "--index", String(tab.id)
        ], timeout: Self.tabTimeout)

        if goToResult.timedOut {
            throw SessionBackendError.timeout(operation: "go-to-tab(\(tab.id))")
        }

        let result = await executor.execute(zellijPath, arguments: [
            "--session", tab.sessionId,
            "action", "close-tab"
        ], timeout: Self.tabTimeout)

        if result.timedOut {
            throw SessionBackendError.timeout(operation: "closeTab(\(tab.id))")
        }

        if !result.succeeded {
            throw SessionBackendError.operationFailed(
                operation: "closeTab",
                reason: result.stderr
            )
        }

        logger.info("Closed tab \(tab.id) in session \(tab.sessionId)")
    }

    // MARK: - Restore

    func sessionExists(_ sessionId: String) async -> Bool {
        // Fast path: check socket first
        guard socketExists(sessionId) else {
            return false
        }

        // Verify it's responsive
        let result = await executor.execute(zellijPath, arguments: [
            "--session", sessionId,
            "action", "query-tab-names"
        ], timeout: Self.healthCheckTimeout)

        return !result.timedOut && result.succeeded
    }

    func resurrectSession(_ sessionId: String) async throws {
        // Just attach - Zellij handles resurrection automatically
        let result = await executor.execute(zellijPath, arguments: [
            "--config", configPath.path,
            "attach", sessionId
        ], timeout: Self.sessionTimeout)

        if result.timedOut {
            throw SessionBackendError.timeout(operation: "resurrectSession(\(sessionId))")
        }

        // Note: User may see "Press ENTER to run..." prompt after resurrection
        // This is expected Zellij behavior for restored sessions
        logger.info("Resurrected session: \(sessionId)")
    }

    // MARK: - Additional Operations

    /// Send text to the focused pane in a session.
    func sendText(_ text: String, to sessionId: String) async throws {
        let result = await executor.execute(zellijPath, arguments: [
            "--session", sessionId,
            "action", "write-chars", text
        ], timeout: Self.listTimeout)

        if result.timedOut {
            throw SessionBackendError.timeout(operation: "sendText")
        }

        if !result.succeeded {
            throw SessionBackendError.operationFailed(
                operation: "sendText",
                reason: result.stderr
            )
        }
    }

    /// Go to a specific tab in a session.
    func goToTab(_ tabId: Int, in sessionId: String) async throws {
        let result = await executor.execute(zellijPath, arguments: [
            "--session", sessionId,
            "action", "go-to-tab", "--index", String(tabId)
        ], timeout: Self.tabTimeout)

        if result.timedOut {
            throw SessionBackendError.timeout(operation: "goToTab(\(tabId))")
        }

        if !result.succeeded {
            throw SessionBackendError.operationFailed(
                operation: "goToTab",
                reason: result.stderr
            )
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
