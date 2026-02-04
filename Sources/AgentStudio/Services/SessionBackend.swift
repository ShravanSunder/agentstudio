// SessionBackend.swift
// AgentStudio
//
// Protocol for session management backends (Zellij, tmux, none, etc.)

import Foundation

// MARK: - Session Handle

/// Handle to a managed session (backend-agnostic).
struct SessionHandle: Identifiable, Hashable, Sendable, Codable {
    /// Unique session identifier (e.g., "agentstudio--abc12345")
    let id: String

    /// Associated project UUID
    let projectId: UUID

    /// Display name (usually repo name)
    let displayName: String

    /// Backend type that created this handle
    let backendType: SessionBackendType

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

/// Protocol for session management backends.
/// Implementations provide session lifecycle, tab management, and health checking.
protocol SessionBackend: Sendable {

    // MARK: - Properties

    /// Backend type identifier.
    var type: SessionBackendType { get }

    /// Check if backend is available and functional.
    var isAvailable: Bool { get async }

    /// Whether this backend supports session persistence/restore.
    var supportsRestore: Bool { get }

    /// Whether this backend supports multiple tabs per session.
    var supportsTabs: Bool { get }

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

    /// Check if a session socket/file exists (fast filesystem check).
    func socketExists(_ sessionId: String) -> Bool

    /// Discover orphan sessions (sessions not in our registry).
    func discoverOrphanSessions(excluding known: Set<String>) -> [String]

    // MARK: - Restore

    /// Check if a session exists and can be attached to.
    func sessionExists(_ sessionId: String) async -> Bool

    /// Resurrect a dead session (for backends that support it).
    func resurrectSession(_ sessionId: String) async throws
}

// MARK: - Default Implementations

extension SessionBackend {

    // Default: no restore support
    var supportsRestore: Bool { false }

    // Default: no tab support
    var supportsTabs: Bool { false }

    // Default tab operations throw unsupported error
    func createTab(in session: SessionHandle, for worktree: Worktree) async throws -> TabHandle {
        throw SessionBackendError.tabsNotSupported(type)
    }

    func getTabNames(_ session: SessionHandle) async throws -> [String] {
        throw SessionBackendError.tabsNotSupported(type)
    }

    func closeTab(_ tab: TabHandle) async throws {
        throw SessionBackendError.tabsNotSupported(type)
    }

    // Default: no socket-based checks
    func socketExists(_ sessionId: String) -> Bool {
        false
    }

    func discoverOrphanSessions(excluding known: Set<String>) -> [String] {
        []
    }

    // Default: no session existence check
    func sessionExists(_ sessionId: String) async -> Bool {
        false
    }

    // Default: no resurrection support
    func resurrectSession(_ sessionId: String) async throws {
        throw SessionBackendError.restoreNotSupported(type)
    }
}

// MARK: - Backend Errors

/// Errors that can occur during backend operations.
enum SessionBackendError: Error, LocalizedError, Equatable {
    case notAvailable(SessionBackendType, reason: String)
    case tabsNotSupported(SessionBackendType)
    case restoreNotSupported(SessionBackendType)
    case sessionNotFound(String)
    case tabNotFound(sessionId: String, tabId: Int)
    case operationFailed(operation: String, reason: String)
    case timeout(operation: String)
    case alreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable(let type, let reason):
            return "\(type.displayName) backend not available: \(reason)"
        case .tabsNotSupported(let type):
            return "\(type.displayName) backend does not support tabs"
        case .restoreNotSupported(let type):
            return "\(type.displayName) backend does not support session restore"
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

// MARK: - Backend Factory

/// Factory for creating session backends.
enum SessionBackendFactory {

    /// Create a backend based on configuration.
    @MainActor
    static func create(for type: SessionBackendType) -> SessionBackend {
        switch type {
        case .zellij:
            return ZellijBackend()
        case .none:
            return NoneBackend()
        }
    }

    /// Create the appropriate backend based on current configuration.
    @MainActor
    static func createFromConfiguration() -> SessionBackend {
        let config = SessionConfiguration.shared
        return create(for: config.backend)
    }
}
