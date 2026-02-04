// SessionBackend.swift
// AgentStudio
//
// Protocol for Zellij session management.

import Foundation

// MARK: - Session Handle

/// Handle to a managed Zellij session.
struct SessionHandle: Identifiable, Hashable, Sendable, Codable {
    /// Unique session identifier (e.g., "agentstudio--abc12345")
    let id: String

    /// Associated project UUID
    let projectId: UUID

    /// Display name (usually repo name)
    let displayName: String

    /// Generate session ID from project UUID.
    static func sessionId(for projectId: UUID) -> String {
        "agentstudio--\(projectId.uuidString.prefix(8).lowercased())"
    }
}

// MARK: - Tab Handle

/// Handle to a tab within a session.
struct TabHandle: Identifiable, Hashable, Sendable, Codable {
    /// Tab index (1-based for Zellij)
    let id: Int

    /// Parent session ID
    let sessionId: String

    /// Associated worktree UUID
    let worktreeId: UUID

    /// Tab name (usually branch name)
    let name: String

    /// Working directory
    let workingDirectory: URL
}

// MARK: - Backend Protocol

/// Protocol for Zellij session management.
/// Used for dependency injection and testing.
protocol SessionBackend: Sendable {

    // MARK: - Availability

    /// Check if backend is available and functional.
    var isAvailable: Bool { get async }

    // MARK: - Session Lifecycle

    /// Create a new session or attach to existing one.
    /// This should be idempotent - safe to call multiple times.
    func createSession(for project: Project) async throws -> SessionHandle

    /// Get the shell command to attach to a session.
    /// This command will be executed by Ghostty.
    func attachCommand(for handle: SessionHandle, tab: TabHandle?) -> String

    /// Destroy a session and clean up resources.
    func destroySession(_ handle: SessionHandle) async throws

    /// Check if a session is alive and responsive.
    func healthCheck(_ handle: SessionHandle) async -> Bool

    // MARK: - Tab Lifecycle

    /// Create a tab in a session for a worktree.
    func createTab(in session: SessionHandle, for worktree: Worktree) async throws -> TabHandle

    /// Get names of all tabs in a session.
    func getTabNames(_ session: SessionHandle) async throws -> [String]

    /// Close a specific tab.
    func closeTab(_ tab: TabHandle) async throws

    // MARK: - Fast Checks (no process spawn)

    /// Check if a session socket exists (fast filesystem check).
    func socketExists(_ sessionId: String) -> Bool

    /// Discover orphan sessions (sessions not in our registry).
    func discoverOrphanSessions(excluding known: Set<String>) -> [String]

    // MARK: - Restore

    /// Check if a session exists and can be attached to.
    func sessionExists(_ sessionId: String) async -> Bool

    /// Resurrect a dead session.
    func resurrectSession(_ sessionId: String) async throws
}

// MARK: - Backend Errors

/// Errors that can occur during session backend operations.
enum SessionBackendError: Error, LocalizedError, Equatable {
    case notAvailable(reason: String)
    case sessionNotFound(String)
    case tabNotFound(sessionId: String, tabId: Int)
    case operationFailed(operation: String, reason: String)
    case timeout(operation: String)
    case alreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable(let reason):
            return "Zellij not available: \(reason)"
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        case .tabNotFound(let sessionId, let tabId):
            return "Tab \(tabId) not found in session \(sessionId)"
        case .operationFailed(let operation, let reason):
            return "\(operation) failed: \(reason)"
        case .timeout(let operation):
            return "\(operation) timed out"
        case .alreadyExists(let id):
            return "Session already exists: \(id)"
        }
    }
}
