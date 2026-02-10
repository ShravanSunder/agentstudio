import Foundation
import os.log

private let runtimeLogger = Logger(subsystem: "com.agentstudio", category: "SessionRuntime")

// MARK: - Session Status

/// Runtime state of a terminal session. Not persisted — derived at runtime.
enum SessionRuntimeStatus: String, Codable, Hashable, Sendable {
    /// Session created, backend not yet ready.
    case initializing
    /// Backend is running and healthy.
    case running
    /// Backend process has exited.
    case exited
    /// Health check failed, session may be stale.
    case unhealthy
}

// MARK: - Session Backend Protocol

/// Abstraction for terminal session providers (Ghostty, tmux, etc.).
/// Concrete implementations handle process lifecycle and health monitoring.
protocol SessionBackendProtocol: Sendable {
    /// Provider type this backend handles.
    var provider: SessionProvider { get }

    /// Start a session. Returns a provider handle for reconnection.
    func start(session: TerminalSession) async throws -> String

    /// Check if a session is still alive.
    func isAlive(session: TerminalSession) async -> Bool

    /// Terminate a session.
    func terminate(session: TerminalSession) async

    /// Attempt to restore a session from its provider handle.
    func restore(session: TerminalSession) async -> Bool
}

// MARK: - Session Runtime

/// Manages live session state. Reads session list from WorkspaceStore (doesn't own it).
/// Tracks runtime status per session, schedules health checks, coordinates backends.
@MainActor
final class SessionRuntime: ObservableObject {

    /// Runtime status for each session.
    @Published private(set) var statuses: [UUID: SessionRuntimeStatus] = [:]

    /// Registered backends by provider type.
    private var backends: [SessionProvider: any SessionBackendProtocol] = [:]

    /// Health check timer interval in seconds.
    private let healthCheckInterval: TimeInterval

    /// Reference to the store (read-only for session list).
    private weak var store: WorkspaceStore?

    /// Health check task.
    private var healthCheckTask: Task<Void, Never>?

    init(
        store: WorkspaceStore? = nil,
        healthCheckInterval: TimeInterval = 30
    ) {
        self.store = store
        self.healthCheckInterval = healthCheckInterval
    }

    deinit {
        healthCheckTask?.cancel()
    }

    // MARK: - Backend Registration

    /// Register a backend for a provider type.
    func registerBackend(_ backend: any SessionBackendProtocol) {
        backends[backend.provider] = backend
    }

    // MARK: - Status Queries

    /// Get the runtime status of a session.
    func status(for sessionId: UUID) -> SessionRuntimeStatus {
        statuses[sessionId] ?? .initializing
    }

    /// All sessions with a given status.
    func sessions(withStatus status: SessionRuntimeStatus) -> [UUID] {
        statuses.filter { $0.value == status }.map(\.key)
    }

    /// Number of running sessions.
    var runningCount: Int {
        statuses.values.filter { $0 == .running }.count
    }

    // MARK: - Lifecycle

    /// Initialize a session — set to initializing state.
    func initializeSession(_ sessionId: UUID) {
        statuses[sessionId] = .initializing
        runtimeLogger.debug("Session \(sessionId) initialized")
    }

    /// Mark a session as running.
    func markRunning(_ sessionId: UUID) {
        statuses[sessionId] = .running
        runtimeLogger.debug("Session \(sessionId) marked running")
    }

    /// Mark a session as exited.
    func markExited(_ sessionId: UUID) {
        statuses[sessionId] = .exited
        runtimeLogger.debug("Session \(sessionId) marked exited")
    }

    /// Remove tracking for a session.
    func removeSession(_ sessionId: UUID) {
        statuses.removeValue(forKey: sessionId)
        runtimeLogger.debug("Session \(sessionId) removed from runtime")
    }

    /// Sync runtime state with store's session list.
    /// Removes statuses for sessions no longer in the store.
    /// Initializes statuses for new sessions.
    func syncWithStore() {
        guard let store else { return }
        let storeSessionIds = Set(store.sessions.map(\.id))
        let trackedIds = Set(statuses.keys)

        // Remove statuses for sessions no longer in store
        for id in trackedIds.subtracting(storeSessionIds) {
            statuses.removeValue(forKey: id)
            runtimeLogger.debug("Removed stale session \(id) from runtime")
        }

        // Add initial status for new sessions
        for id in storeSessionIds.subtracting(trackedIds) {
            statuses[id] = .initializing
            runtimeLogger.debug("Added new session \(id) to runtime")
        }
    }

    // MARK: - Health Checks

    /// Start periodic health checks.
    func startHealthChecks() {
        stopHealthChecks()
        healthCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.healthCheckInterval ?? 30))
                guard !Task.isCancelled else { break }
                await self?.runHealthCheck()
            }
        }
        runtimeLogger.info("Health checks started (interval: \(self.healthCheckInterval)s)")
    }

    /// Stop periodic health checks.
    func stopHealthChecks() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
    }

    /// Run a single health check pass.
    func runHealthCheck() async {
        guard let store else { return }

        for session in store.sessions {
            guard statuses[session.id] == .running else { continue }
            guard let backend = backends[session.provider] else { continue }

            let alive = await backend.isAlive(session: session)
            if !alive {
                statuses[session.id] = .unhealthy
                runtimeLogger.warning("Session \(session.id) unhealthy (\(session.provider.rawValue))")
            }
        }
    }

    // MARK: - Backend Operations

    /// Start a session via its backend.
    func startSession(_ session: TerminalSession) async throws -> String? {
        guard let backend = backends[session.provider] else {
            runtimeLogger.warning("No backend registered for \(session.provider.rawValue)")
            markRunning(session.id) // Ghostty sessions are "running" immediately
            return nil
        }

        statuses[session.id] = .initializing
        let handle = try await backend.start(session: session)
        statuses[session.id] = .running
        return handle
    }

    /// Attempt to restore a session via its backend.
    func restoreSession(_ session: TerminalSession) async -> Bool {
        guard let backend = backends[session.provider] else {
            markRunning(session.id)
            return true
        }

        let restored = await backend.restore(session: session)
        statuses[session.id] = restored ? .running : .exited
        return restored
    }

    /// Terminate a session via its backend.
    func terminateSession(_ session: TerminalSession) async {
        guard let backend = backends[session.provider] else {
            statuses[session.id] = .exited
            return
        }

        await backend.terminate(session: session)
        statuses[session.id] = .exited
    }
}
