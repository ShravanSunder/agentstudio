// NoneBackend.swift
// AgentStudio
//
// No-op backend for when no terminal multiplexer is used.
// Provides direct shell access without session persistence.

import Foundation
import OSLog

/// No-op backend - direct shell without multiplexer.
/// Use this when Zellij is not available or session persistence is not needed.
final class NoneBackend: SessionBackend, @unchecked Sendable {

    // MARK: - Properties

    let type: SessionBackendType = .none
    let supportsRestore: Bool = false
    let supportsTabs: Bool = false

    private let logger = Logger(subsystem: "AgentStudio", category: "NoneBackend")

    // Track "sessions" in memory (just for API consistency, not persisted)
    private var activeSessions: Set<String> = []
    private let lock = NSLock()

    // MARK: - Initialization

    init() {
        logger.info("NoneBackend initialized (no session persistence)")
    }

    // MARK: - Availability

    var isAvailable: Bool {
        get async { true } // Always available
    }

    // MARK: - Session Lifecycle

    func createSession(for project: Project) async throws -> SessionHandle {
        let sessionId = SessionHandle.sessionId(for: project.id)

        lock.lock()
        activeSessions.insert(sessionId)
        lock.unlock()

        logger.info("Created virtual session: \(sessionId)")

        return SessionHandle(
            id: sessionId,
            projectId: project.id,
            displayName: project.name,
            backendType: .none
        )
    }

    func attachCommand(for handle: SessionHandle, tab: TabHandle?) -> String {
        // Just launch the user's shell
        // Working directory is set by Ghostty based on the worktree
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        logger.debug("Attach command for \(handle.id): \(shell)")
        return shell
    }

    func destroySession(_ handle: SessionHandle) async throws {
        lock.lock()
        activeSessions.remove(handle.id)
        lock.unlock()

        logger.info("Destroyed virtual session: \(handle.id)")
    }

    func healthCheck(_ handle: SessionHandle) async -> Bool {
        // Virtual sessions are always "healthy" since there's no actual session
        lock.lock()
        let exists = activeSessions.contains(handle.id)
        lock.unlock()
        return exists
    }

    // MARK: - Fast Checks

    func socketExists(_ sessionId: String) -> Bool {
        // No sockets for NoneBackend
        false
    }

    func discoverOrphanSessions(excluding known: Set<String>) -> [String] {
        // No persistent sessions to discover
        []
    }

    // MARK: - Session Existence

    func sessionExists(_ sessionId: String) async -> Bool {
        lock.lock()
        let exists = activeSessions.contains(sessionId)
        lock.unlock()
        return exists
    }
}

// MARK: - Tab Operations (Not Supported)

extension NoneBackend {
    // These will use the default protocol implementations that throw .tabsNotSupported
    // No need to override them
}
