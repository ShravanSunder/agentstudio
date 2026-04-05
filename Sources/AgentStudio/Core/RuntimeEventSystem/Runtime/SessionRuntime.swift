import Foundation
import Observation
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

/// Abstraction for terminal session providers (Ghostty, zmx, etc.).
/// Concrete implementations handle process lifecycle and health monitoring.
@MainActor
protocol SessionBackendProtocol {
    /// Provider type this backend handles.
    var provider: SessionProvider { get }

    /// Start a session for a pane. Returns a provider handle for reconnection.
    func start(pane: Pane) async throws -> String

    /// Check if a pane's session is still alive.
    func isAlive(pane: Pane) async -> Bool

    /// Terminate a pane's session.
    func terminate(pane: Pane) async

    /// Attempt to restore a pane's session from its provider handle.
    func restore(pane: Pane) async -> Bool
}

// MARK: - Session Runtime

/// Manages live session state. Reads pane list from WorkspaceStore (doesn't own it).
/// Tracks runtime status per pane, schedules health checks, coordinates backends.
@Observable
@MainActor
final class SessionRuntime {
    @ObservationIgnored let atom: SessionRuntimeAtom

    /// Runtime status for each pane.
    var statuses: [UUID: SessionRuntimeStatus] { atom.statuses }

    /// Registered backends by provider type.
    private var backends: [SessionProvider: any SessionBackendProtocol] = [:]

    /// Health check timer interval in seconds.
    private let healthCheckInterval: TimeInterval

    /// Clock for scheduling health checks without hard-coding Task.sleep.
    private let clock: any Clock<Duration>

    /// Reference to the store (read-only for pane list).
    private weak var store: WorkspaceStore?

    /// Health check task.
    private var healthCheckTask: Task<Void, Never>?

    init(
        atom: SessionRuntimeAtom = SessionRuntimeAtom(),
        store: WorkspaceStore? = nil,
        healthCheckInterval: TimeInterval = 30,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.atom = atom
        self.store = store
        self.healthCheckInterval = healthCheckInterval
        self.clock = clock
    }

    isolated deinit {
        stopHealthChecks()
    }

    // MARK: - Backend Registration

    /// Register a backend for a provider type.
    func registerBackend(_ backend: any SessionBackendProtocol) {
        backends[backend.provider] = backend
    }

    // MARK: - Status Queries

    /// Get the runtime status of a pane.
    func status(for paneId: UUID) -> SessionRuntimeStatus {
        atom.status(for: paneId)
    }

    /// All panes with a given status.
    func panes(withStatus status: SessionRuntimeStatus) -> [UUID] {
        atom.panes(withStatus: status)
    }

    /// Number of running panes.
    var runningCount: Int {
        atom.runningCount
    }

    // MARK: - Lifecycle

    /// Initialize a pane — set to initializing state.
    func initializeSession(_ paneId: UUID) {
        atom.initializeSession(paneId)
        runtimeLogger.debug("Pane \(paneId) initialized")
    }

    /// Mark a pane as running.
    func markRunning(_ paneId: UUID) {
        atom.markRunning(paneId)
        runtimeLogger.debug("Pane \(paneId) marked running")
    }

    /// Mark a pane as exited.
    func markExited(_ paneId: UUID) {
        atom.markExited(paneId)
        runtimeLogger.debug("Pane \(paneId) marked exited")
    }

    /// Remove tracking for a pane.
    func removeSession(_ paneId: UUID) {
        atom.removeSession(paneId)
        runtimeLogger.debug("Pane \(paneId) removed from runtime")
    }

    /// Sync runtime state with store's pane list.
    /// Removes statuses for panes no longer in the store.
    /// Initializes statuses for new panes.
    func syncWithStore() {
        guard let store else { return }
        let storePaneIds = Set(store.panes.keys)
        atom.sync(withPaneIds: storePaneIds)
    }

    // MARK: - Health Checks

    /// Start periodic health checks.
    func startHealthChecks() {
        stopHealthChecks()
        healthCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                try? await self.clock.sleep(for: .seconds(self.healthCheckInterval))
                guard !Task.isCancelled else { break }
                await self.runHealthCheck()
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

        for (id, pane) in store.panes {
            guard atom.status(for: id) == .running else { continue }
            guard let provider = pane.provider,
                let backend = backends[provider]
            else { continue }

            let alive = await backend.isAlive(pane: pane)
            if !alive {
                atom.markUnhealthy(id)
                runtimeLogger.warning("Pane \(id) unhealthy (\(provider.rawValue))")
            }
        }
    }

    // MARK: - Backend Operations

    /// Start a session for a pane via its backend.
    func startSession(_ pane: Pane) async throws -> String? {
        guard let provider = pane.provider,
            let backend = backends[provider]
        else {
            runtimeLogger.warning("No backend registered for pane \(pane.id)")
            markExited(pane.id)
            return nil
        }

        atom.initializeSession(pane.id)
        let handle = try await backend.start(pane: pane)
        atom.markRunning(pane.id)
        return handle
    }

    /// Attempt to restore a pane's session via its backend.
    func restoreSession(_ pane: Pane) async -> Bool {
        guard let provider = pane.provider,
            let backend = backends[provider]
        else {
            markExited(pane.id)
            return false
        }

        let restored = await backend.restore(pane: pane)
        if restored {
            atom.markRunning(pane.id)
        } else {
            atom.markExited(pane.id)
        }
        return restored
    }

    /// Terminate a pane's session via its backend.
    func terminateSession(_ pane: Pane) async {
        guard let provider = pane.provider,
            let backend = backends[provider]
        else {
            atom.markExited(pane.id)
            return
        }

        await backend.terminate(pane: pane)
        atom.markExited(pane.id)
    }
}
