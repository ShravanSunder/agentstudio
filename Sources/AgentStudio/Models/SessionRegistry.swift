// SessionRegistry.swift
// AgentStudio
//
// Central registry for all session state, using state machines for lifecycle management.

import Foundation
import OSLog

// MARK: - Session Entry

/// Entry for a session in the registry.
@MainActor
@Observable
final class SessionEntry: Identifiable, @unchecked Sendable {

    // MARK: - Properties

    /// Unique session identifier (e.g., "agentstudio--abc12345")
    let id: String

    /// Associated project UUID
    let projectId: UUID

    /// Display name (usually repo name)
    var displayName: String

    /// State machine managing session lifecycle
    let machine: Machine<SessionStatus>

    /// Tabs within this session, keyed by worktree ID
    var tabs: [UUID: TabEntry] = [:]

    // MARK: - Computed Properties

    /// Current session status
    var status: SessionStatus { machine.state }

    /// Whether the session is ready for use
    var isReady: Bool { status.isReady }

    /// Whether the session needs recovery
    var needsRecovery: Bool { status.needsRecovery }

    // MARK: - Initialization

    init(id: String, projectId: UUID, displayName: String, initialStatus: SessionStatus = .unknown) {
        self.id = id
        self.projectId = projectId
        self.displayName = displayName
        self.machine = Machine(initial: initialStatus)
    }
}

// MARK: - Tab Entry

/// Entry for a tab within a session.
@MainActor
@Observable
final class TabEntry: Identifiable, @unchecked Sendable {

    // MARK: - Properties

    /// Tab index (1-based for Zellij)
    var id: Int

    /// Associated worktree UUID
    let worktreeId: UUID

    /// Tab name (usually branch name)
    var name: String

    /// Working directory path
    var workingDirectory: String

    /// Command to re-run on restore
    var restoreCommand: String?

    /// Original order from checkpoint (for preserving tab order)
    var originalOrder: Int

    /// State machine managing tab lifecycle
    let machine: Machine<TabStatus>

    // MARK: - Computed Properties

    /// Current tab status
    var status: TabStatus { machine.state }

    /// Whether the tab is ready for use
    var isReady: Bool { status.isReady }

    // MARK: - Initialization

    init(
        id: Int,
        worktreeId: UUID,
        name: String,
        workingDirectory: String,
        restoreCommand: String? = nil,
        originalOrder: Int,
        initialStatus: TabStatus = .unknown
    ) {
        self.id = id
        self.worktreeId = worktreeId
        self.name = name
        self.workingDirectory = workingDirectory
        self.restoreCommand = restoreCommand
        self.originalOrder = originalOrder
        self.machine = Machine(initial: initialStatus)
    }
}

// MARK: - Session Registry

/// Central registry for all session state.
@MainActor
@Observable
final class SessionRegistry: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = SessionRegistry()

    // MARK: - Properties

    /// All registered sessions, keyed by session ID
    private(set) var sessions: [String: SessionEntry] = [:]

    /// Whether initialization is complete
    private(set) var isInitialized: Bool = false

    /// Whether background verification is in progress
    private(set) var isVerifying: Bool = false

    /// Last verification timestamp
    private(set) var lastVerificationTime: Date?

    /// Configuration reference
    private let config: SessionConfiguration

    /// Logger
    private let logger = Logger(subsystem: "AgentStudio", category: "SessionRegistry")

    /// Active backend
    private(set) var backend: SessionBackend!

    /// Health check timer
    private var healthCheckTask: Task<Void, Never>?

    // MARK: - Initialization

    private init() {
        self.config = SessionConfiguration.shared
    }

    // MARK: - Public API

    /// Initialize the registry. Call once at app startup.
    func initialize() async {
        guard !isInitialized else {
            logger.warning("SessionRegistry already initialized")
            return
        }

        logger.info("Initializing SessionRegistry...")

        // Detect Zellij availability and socket directory
        await config.detectZellij()

        // Only initialize backend if session restore is enabled
        guard config.sessionRestoreEnabled else {
            logger.info("Session restore disabled, skipping Zellij initialization")
            isInitialized = true
            return
        }

        // Create Zellij backend
        backend = ZellijBackend()
        logger.info("Session backend: Zellij")

        // Load checkpoint
        if let checkpoint = loadCheckpoint() {
            populateFromCheckpoint(checkpoint)
        }

        isInitialized = true
        logger.info("SessionRegistry initialized with \(self.sessions.count) sessions")

        // Start background verification
        if !sessions.isEmpty {
            await verifyAllSessions()
            startHealthChecks()
        }
    }

    /// Get or create a session for a project.
    func getOrCreateSession(for project: Project) async throws -> SessionEntry {
        let sessionId = SessionHandle.sessionId(for: project.id)

        // Check if already exists in registry
        if let existing = sessions[sessionId] {
            // If not ready, trigger recovery
            if existing.needsRecovery {
                await existing.machine.send(.startRecovery(sessionId: sessionId, projectId: project.id))
            }
            return existing
        }

        // Create new session via backend
        let handle = try await backend.createSession(for: project)

        // Create registry entry
        let entry = SessionEntry(
            id: handle.id,
            projectId: handle.projectId,
            displayName: handle.displayName,
            initialStatus: .alive
        )

        // Wire up effect handler
        setupEffectHandler(for: entry)

        sessions[handle.id] = entry
        logger.info("Created session entry: \(handle.id)")

        return entry
    }

    /// Get session for a project (if exists).
    func session(for projectId: UUID) -> SessionEntry? {
        let sessionId = SessionHandle.sessionId(for: projectId)
        return sessions[sessionId]
    }

    /// Get or create a tab for a worktree.
    func getOrCreateTab(in session: SessionEntry, for worktree: Worktree) async throws -> TabEntry {
        // Check if tab already exists
        if let existing = session.tabs[worktree.id] {
            // If needs creation, trigger it
            if existing.status.needsCreation {
                await existing.machine.send(.startCreation(sessionId: session.id, worktreeId: worktree.id))
            }
            return existing
        }

        // Create tab via backend
        guard backend != nil else {
            // For backends without tab support, create a virtual tab
            let entry = TabEntry(
                id: 1,
                worktreeId: worktree.id,
                name: worktree.branch,
                workingDirectory: worktree.path.path,
                originalOrder: session.tabs.count,
                initialStatus: .unsupported
            )
            session.tabs[worktree.id] = entry
            return entry
        }

        let handle = SessionHandle(
            id: session.id,
            projectId: session.projectId,
            displayName: session.displayName        )

        let tabHandle = try await backend.createTab(in: handle, for: worktree)

        let entry = TabEntry(
            id: tabHandle.id,
            worktreeId: tabHandle.worktreeId,
            name: tabHandle.name,
            workingDirectory: tabHandle.workingDirectory.path,
            originalOrder: session.tabs.count,
            initialStatus: .verified
        )

        // Wire up effect handler
        setupTabEffectHandler(for: entry, in: session)

        session.tabs[worktree.id] = entry
        logger.info("Created tab entry: \(tabHandle.name) in session \(session.id)")

        return entry
    }

    /// Get the attach command for a session/tab combination.
    func attachCommand(for session: SessionEntry, tab: TabEntry?) -> String {
        let handle = SessionHandle(
            id: session.id,
            projectId: session.projectId,
            displayName: session.displayName        )

        var tabHandle: TabHandle?
        if let tab = tab {
            tabHandle = TabHandle(
                id: tab.id,
                sessionId: session.id,
                worktreeId: tab.worktreeId,
                name: tab.name,
                workingDirectory: URL(fileURLWithPath: tab.workingDirectory)
            )
        }

        return backend.attachCommand(for: handle, tab: tabHandle)
    }

    /// Destroy a session.
    func destroySession(_ session: SessionEntry) async throws {
        let handle = SessionHandle(
            id: session.id,
            projectId: session.projectId,
            displayName: session.displayName        )

        try await backend.destroySession(handle)
        sessions.removeValue(forKey: session.id)
        logger.info("Destroyed session: \(session.id)")
    }

    // MARK: - Verification

    /// Verify all sessions (background operation).
    func verifyAllSessions() async {
        guard !isVerifying else {
            logger.debug("Verification already in progress")
            return
        }

        isVerifying = true
        defer {
            isVerifying = false
            lastVerificationTime = Date()
        }

        logger.info("Starting session verification for \(self.sessions.count) sessions")

        // Phase 1: Fast socket check (no process spawn)
        for (sessionId, entry) in sessions {
            if entry.status == .unknown {
                await entry.machine.send(.startVerification(sessionId: sessionId))
            }
        }

        // Phase 2: Discover orphans
        let knownIds = Set(sessions.keys)
        let orphans = backend.discoverOrphanSessions(excluding: knownIds)

        for orphanId in orphans {
            let entry = SessionEntry(
                id: orphanId,
                projectId: UUID(), // Unknown project
                displayName: "Orphan: \(orphanId)",
                initialStatus: .orphan
            )
            sessions[orphanId] = entry
            logger.info("Added orphan session: \(orphanId)")
        }

        // Phase 3: Wait for state machines to settle
        // The effect handlers will drive the verification forward

        logger.info("Session verification complete")
    }

    /// Start periodic health checks.
    func startHealthChecks() {
        guard healthCheckTask == nil else { return }

        let interval = config.healthCheckInterval
        logger.info("Starting health checks with interval: \(interval)s")

        healthCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

                guard let self = self else { break }

                await self.performHealthChecks()
            }
        }
    }

    /// Stop health checks.
    func stopHealthChecks() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
        logger.info("Stopped health checks")
    }

    // MARK: - Checkpoint

    /// Save checkpoint to disk.
    func saveCheckpoint() {
        guard backend?.supportsRestore == true else { return }

        let sessionsData = sessions.values.compactMap { entry -> SessionCheckpoint.SessionData? in
            guard entry.status == .alive else { return nil }

            let tabsData = entry.tabs.values
                .sorted { $0.originalOrder < $1.originalOrder }
                .map { tab in
                    SessionCheckpoint.TabData(
                        id: tab.id,
                        name: tab.name,
                        worktreeId: tab.worktreeId,
                        workingDirectory: tab.workingDirectory,
                        restoreCommand: tab.restoreCommand,
                        order: tab.originalOrder
                    )
                }

            return SessionCheckpoint.SessionData(
                id: entry.id,
                projectId: entry.projectId,
                displayName: entry.displayName,
                tabs: tabsData,
                lastKnownAlive: Date()
            )
        }

        let checkpoint = SessionCheckpoint(
            version: SessionCheckpoint.currentVersion,
            timestamp: Date(),
            sessions: sessionsData,
            zellijSocketDir: config.socketDir.path
        )

        do {
            let data = try JSONEncoder().encode(checkpoint)
            let url = checkpointURL
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
            logger.info("Saved checkpoint with \(sessionsData.count) sessions")
        } catch {
            logger.error("Failed to save checkpoint: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods

    private var checkpointURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".agentstudio/session-checkpoint.json")
    }

    private func loadCheckpoint() -> SessionCheckpoint? {
        let url = checkpointURL

        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.info("No checkpoint file found")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let checkpoint = try JSONDecoder().decode(SessionCheckpoint.self, from: data)
            logger.info("Loaded checkpoint with \(checkpoint.sessions.count) sessions")
            return checkpoint
        } catch {
            logger.error("Failed to load checkpoint: \(error.localizedDescription)")
            return nil
        }
    }

    private func populateFromCheckpoint(_ checkpoint: SessionCheckpoint) {
        for sessionData in checkpoint.sessions {
            let entry = SessionEntry(
                id: sessionData.id,
                projectId: sessionData.projectId,
                displayName: sessionData.displayName,
                initialStatus: .unknown
            )

            // Wire up effect handler
            setupEffectHandler(for: entry)

            // Populate tabs
            for tabData in sessionData.tabs {
                let tabEntry = TabEntry(
                    id: tabData.id,
                    worktreeId: tabData.worktreeId,
                    name: tabData.name,
                    workingDirectory: tabData.workingDirectory,
                    restoreCommand: tabData.restoreCommand,
                    originalOrder: tabData.order ?? 0,
                    initialStatus: .unknown
                )

                setupTabEffectHandler(for: tabEntry, in: entry)
                entry.tabs[tabData.worktreeId] = tabEntry
            }

            sessions[sessionData.id] = entry
        }

        logger.info("Populated \(self.sessions.count) sessions from checkpoint")
    }

    private func setupEffectHandler(for entry: SessionEntry) {
        entry.machine.effectHandler = { [weak self, weak entry] effect in
            guard let self = self, let entry = entry else { return }
            await self.handleSessionEffect(effect, for: entry)
        }
    }

    private func setupTabEffectHandler(for tabEntry: TabEntry, in sessionEntry: SessionEntry) {
        tabEntry.machine.effectHandler = { [weak self, weak sessionEntry] effect in
            guard let self = self, let sessionEntry = sessionEntry else { return }
            await self.handleTabEffect(effect, for: tabEntry, in: sessionEntry)
        }
    }

    private func handleSessionEffect(_ effect: SessionEffect, for entry: SessionEntry) async {
        switch effect {
        case .checkSocket(let sessionId):
            let exists = backend.socketExists(sessionId)
            if exists {
                await entry.machine.send(.socketFound(sessionId: sessionId))
            } else {
                await entry.machine.send(.socketNotFound)
            }

        case .tryAttach(let sessionId):
            let alive = await backend.sessionExists(sessionId)
            if alive {
                await entry.machine.send(.attachSucceeded(sessionId: sessionId))
            } else {
                await entry.machine.send(.attachFailed(reason: "Socket not responsive"))
            }

        case .resurrect(let sessionId, _):
            do {
                try await backend.resurrectSession(sessionId)
                await entry.machine.send(.recoverySucceeded(sessionId: sessionId))
            } catch {
                await entry.machine.send(.recoveryFailed(
                    sessionId: sessionId,
                    projectId: entry.projectId,
                    reason: error.localizedDescription
                ))
            }

        case .createSession(let sessionId, let projectId):
            do {
                // We need project info - for now just use what we have
                let project = Project(
                    id: projectId,
                    name: entry.displayName,
                    repoPath: URL(fileURLWithPath: "/tmp") // Placeholder
                )
                _ = try await backend.createSession(for: project)
                await entry.machine.send(.recoverySucceeded(sessionId: sessionId))
            } catch {
                await entry.machine.send(.recoveryFailed(
                    sessionId: sessionId,
                    projectId: projectId,
                    reason: error.localizedDescription
                ))
            }

        case .notifyReady(let sessionId):
            logger.info("Session ready: \(sessionId)")
            // Verify tabs now that session is alive
            await verifyTabs(for: entry)

        case .notifyFailed(let reason):
            logger.error("Session failed: \(reason)")

        case .scheduleHealthCheck(let sessionId, let delay):
            // Health checks are handled by the periodic task
            logger.debug("Health check scheduled for \(sessionId) in \(delay)s")

        case .log(let level, let message):
            switch level {
            case .debug: logger.debug("\(message)")
            case .info: logger.info("\(message)")
            case .warning: logger.warning("\(message)")
            case .error: logger.error("\(message)")
            }
        }
    }

    private func handleTabEffect(_ effect: TabEffect, for tabEntry: TabEntry, in sessionEntry: SessionEntry) async {
        switch effect {
        case .queryTabExists(let sessionId):
            guard backend != nil else {
                await tabEntry.machine.send(.disable)
                return
            }

            let handle = SessionHandle(
                id: sessionId,
                projectId: sessionEntry.projectId,
                displayName: sessionEntry.displayName
            )

            do {
                let tabNames = try await backend.getTabNames(handle)
                if tabNames.contains(tabEntry.name) {
                    // Find the tab ID
                    if let index = tabNames.firstIndex(of: tabEntry.name) {
                        await tabEntry.machine.send(.found(tabId: index + 1)) // 1-based
                    } else {
                        await tabEntry.machine.send(.notFound)
                    }
                } else {
                    await tabEntry.machine.send(.notFound)
                }
            } catch {
                logger.warning("Failed to query tabs: \(error.localizedDescription)")
                await tabEntry.machine.send(.notFound)
            }

        case .createTab(let sessionId, let worktreeId):
            // This would need the actual worktree - simplified for now
            logger.info("Tab creation requested for \(worktreeId) in \(sessionId)")

        case .updateTabId(let tabId):
            tabEntry.id = tabId

        case .notifyReady(let tabId):
            logger.info("Tab ready: \(tabId)")

        case .notifyFailed(let reason):
            logger.error("Tab failed: \(reason)")
        }
    }

    private func verifyTabs(for session: SessionEntry) async {
        guard backend != nil else { return }

        for (_, tab) in session.tabs {
            if tab.status == .unknown {
                await tab.machine.send(.startVerification(sessionId: session.id))
            }
        }
    }

    private func performHealthChecks() async {
        for (_, entry) in sessions {
            guard entry.status == .alive else { continue }

            let handle = SessionHandle(
                id: entry.id,
                projectId: entry.projectId,
                displayName: entry.displayName
            )

            let healthy = await backend.healthCheck(handle)
            if healthy {
                await entry.machine.send(.healthCheckPassed(sessionId: entry.id))
            } else {
                await entry.machine.send(.healthCheckFailed)
            }
        }
    }
}
