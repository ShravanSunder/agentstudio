import Foundation
import Observation
import os.log

private let sidebarCacheStoreLogger = Logger(subsystem: "com.agentstudio", category: "SidebarCacheStore")

@MainActor
final class SidebarCacheStore {
    private let atom: SidebarCacheState
    private let sqliteDatastore: WorkspaceSQLiteDatastore
    private let persistDebounceDuration: Duration
    private let delay: AsyncDelay
    private let recoveryReporter: PersistenceRecoveryReporter?
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingCacheState = false
    private var isRestoringState = false
    private var activeWorkspaceId: UUID?
    var isAutosaveObservationActive: Bool {
        isObservingCacheState
    }

    init(
        atom: SidebarCacheState,
        sqliteDatastore: WorkspaceSQLiteDatastore,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: (any Clock<Duration> & Sendable)? = nil,
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.atom = atom
        self.sqliteDatastore = sqliteDatastore
        self.persistDebounceDuration = persistDebounceDuration
        delay = clock.map(AsyncDelay.clock) ?? .taskSleep
        self.recoveryReporter = recoveryReporter
    }

    /// Begin observing atom mutations for debounced autosave.
    ///
    /// The owner arms observation after restore-time mutations are complete; see
    /// `RepoCacheStore.startObserving` for the boot-order rationale.
    func startObserving() {
        observeCacheState()
    }

    func restoreAsync(for workspaceId: UUID) async {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        activeWorkspaceId = workspaceId
        switch await sqliteDatastore.loadSidebarState(workspaceContextId: workspaceId) {
        case .loaded(let payload):
            isRestoringState = true
            atom.setExpandedGroups(payload.expandedGroups)
            isRestoringState = false
            reportRecoveryEvents(payload.recoveryEvents)
        case .unavailable(let failure, let recoveryEvents):
            isRestoringState = false
            atom.clear()
            reportRecoveryEvents(recoveryEvents)
            sidebarCacheStoreLogger.warning("Sidebar cache SQLite restore failed: \(failure.description)")
            recoveryReporter?(
                .init(
                    store: .sidebarCache,
                    workspaceId: workspaceId,
                    recovery: .resetToDefaults
                )
            )
        }
    }

    func flushAsync(for workspaceId: UUID) async throws {
        activeWorkspaceId = workspaceId
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        try await persistNow(for: workspaceId)
    }

    private func observeCacheState() {
        guard !isObservingCacheState else { return }
        isObservingCacheState = true
        withObservationTracking {
            _ = atom.expandedGroups
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                // SidebarCacheState is @MainActor; this traps if that ownership changes.
                guard let self else { return }
                let shouldIgnore = self.isRestoringState
                self.isObservingCacheState = false
                self.observeCacheState()
                guard !shouldIgnore else { return }
                self.schedulePersist()
            }
        }
    }

    private func schedulePersist() {
        guard let workspaceId = activeWorkspaceId else { return }
        debouncedSaveTask?.cancel()
        let delay = self.delay
        let persistDebounceDuration = self.persistDebounceDuration
        debouncedSaveTask = Task { @MainActor [weak self, delay, persistDebounceDuration, workspaceId] in
            try? await delay.wait(persistDebounceDuration)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            do {
                try await self.persistNow(for: workspaceId)
            } catch {
                sidebarCacheStoreLogger.warning("Sidebar cache autosave failed: \(error.localizedDescription)")
            }
        }
    }

    private func persistNow(for workspaceId: UUID) async throws {
        do {
            try await sqliteDatastore.saveSidebarState(
                expandedGroups: atom.expandedGroups,
                workspaceContextId: workspaceId
            )
        } catch {
            reportSaveFailed(workspaceId: workspaceId)
            throw error
        }
    }

    private func reportSaveFailed(workspaceId: UUID) {
        recoveryReporter?(
            .init(store: .sidebarCache, workspaceId: workspaceId, recovery: .saveFailed)
        )
    }

    private func reportRecoveryEvents(_ recoveryEvents: [PersistenceRecoveryEvent]) {
        for recoveryEvent in recoveryEvents {
            recoveryReporter?(recoveryEvent)
        }
    }
}
