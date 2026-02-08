import Foundation

/// Central orchestrator for pane session lifecycle management.
/// Owns all state machines, drives them through the SessionBackend,
/// and persists checkpoints.
@MainActor
final class SessionRegistry {
    static let shared = SessionRegistry()

    private(set) var configuration: SessionConfiguration
    private(set) var backend: (any SessionBackend)?
    private(set) var entries: [String: PaneEntry] = [:]
    private var healthCheckTasks: [String: Task<Void, Never>] = [:]

    private init() {
        self.configuration = .detect()
    }

    // MARK: - Entry Type

    /// A tracked pane session with its state machine.
    struct PaneEntry {
        let handle: PaneSessionHandle
        let machine: Machine<SessionStatus>
    }

    // MARK: - Initialization

    /// Initialize the registry: detect config, create backend, load checkpoint, verify sessions.
    func initialize() async {
        configuration = .detect()

        guard configuration.isOperational else {
            backend = nil
            return
        }

        let tmuxBackend = TmuxBackend(
            executor: DefaultProcessExecutor(),
            ghostConfigPath: configuration.ghostConfigPath
        )

        guard await tmuxBackend.isAvailable else {
            backend = nil
            return
        }

        backend = tmuxBackend

        // Load checkpoint and verify surviving sessions
        if let checkpoint = SessionCheckpoint.load(), !checkpoint.isStale() {
            await restoreFromCheckpoint(checkpoint)
        }
    }

    // MARK: - Pane Session Management

    /// Get an existing pane session for a worktree, or create one.
    func getOrCreatePaneSession(
        for worktree: Worktree,
        in project: Project
    ) async throws -> PaneEntry {
        let expectedId = TmuxBackend.sessionId(projectId: project.id, worktreeId: worktree.id)

        // Return existing if alive
        if let existing = entries[expectedId], existing.machine.state == .alive {
            return existing
        }

        guard let backend else {
            throw SessionBackendError.notAvailable
        }

        let handle = try await backend.createPaneSession(projectId: project.id, worktree: worktree)
        let machine = Machine<SessionStatus>(initialState: .unknown)
        machine.setEffectHandler { [weak self] effect in
            await self?.handleSessionEffect(effect, sessionId: handle.id)
        }

        let entry = PaneEntry(handle: handle, machine: machine)
        entries[handle.id] = entry

        // Drive to alive
        await machine.send(.create)
        await machine.send(.created)

        scheduleHealthCheck(for: handle.id)
        saveCheckpoint()

        return entry
    }

    /// Register a pane session for tracking without creating it via tmux CLI.
    /// The GhosttyKit surface will create the tmux session via `new-session -A`.
    func registerPaneSession(
        id: String,
        projectId: UUID,
        worktreeId: UUID,
        displayName: String,
        workingDirectory: URL
    ) {
        guard entries[id] == nil else { return }

        let handle = PaneSessionHandle(
            id: id,
            projectId: projectId,
            worktreeId: worktreeId,
            displayName: displayName,
            workingDirectory: workingDirectory
        )

        let machine = Machine<SessionStatus>(initialState: .alive)
        machine.setEffectHandler { [weak self] effect in
            await self?.handleSessionEffect(effect, sessionId: id)
        }

        entries[id] = PaneEntry(handle: handle, machine: machine)
        scheduleHealthCheck(for: id)
        saveCheckpoint()
    }

    /// Returns the command Ghostty should run for a worktree's pane session.
    func attachCommand(for worktree: Worktree, in project: Project) -> String? {
        guard let backend else { return nil }

        let expectedId = TmuxBackend.sessionId(projectId: project.id, worktreeId: worktree.id)
        guard let entry = entries[expectedId] else { return nil }

        return backend.attachCommand(for: entry.handle)
    }

    // MARK: - Checkpoint

    /// Save current state to disk. This is the sole checkpoint writer.
    func saveCheckpoint() {
        let sessionData = entries.values.map { entry in
            SessionCheckpoint.PaneSessionData(
                sessionId: entry.handle.id,
                projectId: entry.handle.projectId,
                worktreeId: entry.handle.worktreeId,
                displayName: entry.handle.displayName,
                workingDirectory: entry.handle.workingDirectory,
                lastKnownAlive: Date()
            )
        }

        let checkpoint = SessionCheckpoint(sessions: sessionData)
        try? checkpoint.save()
    }

    // MARK: - Cleanup

    /// Cancel all health check timers. Call on app termination.
    func stopHealthChecks() {
        for (_, task) in healthCheckTasks {
            task.cancel()
        }
        healthCheckTasks.removeAll()
    }

    /// Destroy all managed sessions. For testing or full cleanup.
    func destroyAll() async {
        stopHealthChecks()
        guard let backend else { return }

        for entry in entries.values {
            try? await backend.destroyPaneSession(entry.handle)
        }
        entries.removeAll()

        // Remove checkpoint file
        try? FileManager.default.removeItem(at: SessionCheckpoint.defaultPath)
    }

    // MARK: - Private: Checkpoint Restore

    private func restoreFromCheckpoint(_ checkpoint: SessionCheckpoint) async {
        guard let backend else { return }

        for sessionData in checkpoint.sessions {
            let handle = PaneSessionHandle(
                id: sessionData.sessionId,
                projectId: sessionData.projectId,
                worktreeId: sessionData.worktreeId,
                displayName: sessionData.displayName,
                workingDirectory: sessionData.workingDirectory
            )

            let alive = await backend.sessionExists(handle)
            guard alive else { continue }

            let machine = Machine<SessionStatus>(initialState: .alive)
            machine.setEffectHandler { [weak self] effect in
                await self?.handleSessionEffect(effect, sessionId: handle.id)
            }

            entries[handle.id] = PaneEntry(handle: handle, machine: machine)
            scheduleHealthCheck(for: handle.id)
        }
    }

    // MARK: - Private: Health Checks

    private func scheduleHealthCheck(for sessionId: String) {
        healthCheckTasks[sessionId]?.cancel()

        healthCheckTasks[sessionId] = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.configuration.healthCheckInterval ?? 30))
                guard !Task.isCancelled else { return }
                await self?.performHealthCheck(for: sessionId)
            }
        }
    }

    private func performHealthCheck(for sessionId: String) async {
        guard let backend, let entry = entries[sessionId] else { return }

        let alive = await backend.healthCheck(entry.handle)
        if alive {
            await entry.machine.send(.healthCheckPassed)
        } else {
            await entry.machine.send(.healthCheckFailed)
            healthCheckTasks[sessionId]?.cancel()
            healthCheckTasks.removeValue(forKey: sessionId)
        }
    }

    // MARK: - Private: Effect Handlers

    private func handleSessionEffect(_ effect: SessionStatus.Effect, sessionId: String) async {
        guard let backend, let entry = entries[sessionId] else { return }

        switch effect {
        case .checkSocket:
            let exists = backend.socketExists()
            if exists {
                await entry.machine.send(.socketFound)
            } else {
                await entry.machine.send(.socketMissing)
            }

        case .checkSessionExists:
            let exists = await backend.sessionExists(entry.handle)
            if exists {
                await entry.machine.send(.sessionDetected)
            } else {
                await entry.machine.send(.sessionNotDetected)
            }

        case .createSession:
            // Session already created via getOrCreatePaneSession
            break

        case .destroySession:
            try? await backend.destroyPaneSession(entry.handle)

        case .scheduleHealthCheck:
            scheduleHealthCheck(for: sessionId)

        case .cancelHealthCheck:
            healthCheckTasks[sessionId]?.cancel()
            healthCheckTasks.removeValue(forKey: sessionId)

        case .attemptRecovery:
            let alive = await backend.healthCheck(entry.handle)
            if alive {
                await entry.machine.send(.recoverySucceeded)
            } else {
                await entry.machine.send(.recoveryFailed(reason: "Session did not recover"))
            }

        case .notifyAlive, .notifyDead, .notifyFailed:
            break
        }
    }

    // MARK: - Testing Support

    /// Reset for testing. Not for production use.
    func _resetForTesting(
        configuration: SessionConfiguration? = nil,
        backend: (any SessionBackend)? = nil
    ) {
        stopHealthChecks()
        entries.removeAll()
        if let configuration { self.configuration = configuration }
        self.backend = backend
    }
}
