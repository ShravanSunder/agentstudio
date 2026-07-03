import Foundation
import Observation
import os.log

private let sidebarCacheStoreLogger = Logger(subsystem: "com.agentstudio", category: "SidebarCacheStore")

@MainActor
final class SidebarCacheStore {
    private let atom: SidebarCacheState
    private let persistor: WorkspacePersistor
    private let sqliteDatastore: WorkspaceSQLiteDatastore?
    private let persistDebounceDuration: Duration
    private let delay: AsyncDelay
    private let recoveryReporter: PersistenceRecoveryReporter?
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingCacheState = false
    private var isRestoringState = false
    private var activeWorkspaceId: UUID?
    private(set) var canArchiveLegacySidebarCacheFile = true

    var isAutosaveObservationActive: Bool {
        isObservingCacheState
    }

    init(
        atom: SidebarCacheState,
        persistor: WorkspacePersistor = WorkspacePersistor(),
        sqliteDatastore: WorkspaceSQLiteDatastore? = nil,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: (any Clock<Duration> & Sendable)? = nil,
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.atom = atom
        self.persistor = persistor
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

    func restore(for workspaceId: UUID) {
        guard sqliteDatastore == nil else {
            preconditionFailure("Use await restoreAsync(for:) when SQLite datastore is enabled")
        }
        restoreFromLegacyFiles(workspaceId: workspaceId, legacyImportDecision: .allowImport)
    }

    func restoreAsync(for workspaceId: UUID) async {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        activeWorkspaceId = workspaceId
        canArchiveLegacySidebarCacheFile = true
        if let sqliteDatastore {
            switch await restoreFromSQLite(for: workspaceId, sqliteDatastore: sqliteDatastore) {
            case .restored:
                return
            case .missing(let legacyImportDecision, let recoveryEvents):
                reportRecoveryEvents(recoveryEvents)
                await restoreFromLegacyFilesAsync(workspaceId: workspaceId, legacyImportDecision: legacyImportDecision)
                return
            case .unavailable(let recoveryEvents):
                reportRecoveryEvents(recoveryEvents)
                atom.clear()
                canArchiveLegacySidebarCacheFile = false
                recoveryReporter?(
                    .init(store: .sidebarCache, workspaceId: workspaceId, recovery: .resetToDefaults)
                )
                return
            }
        }
        restoreFromLegacyFiles(workspaceId: workspaceId, legacyImportDecision: .allowImport)
    }

    private func restoreFromLegacyFiles(
        workspaceId: UUID,
        legacyImportDecision: WorkspaceLocalSQLiteLegacyImportDecision
    ) {
        guard legacyImportDecision.allowsLegacyImport else {
            atom.clear()
            canArchiveLegacySidebarCacheFile = !persistor.hasLegacySidebarCacheFile(for: workspaceId)
            recoveryReporter?(
                .init(store: .sidebarCache, workspaceId: workspaceId, recovery: .resetToDefaults)
            )
            return
        }
        switch persistor.loadSidebarCache(for: workspaceId) {
        case .loaded(let state):
            isRestoringState = true
            atom.setExpandedGroups(state.expandedGroups)
            isRestoringState = false
            canArchiveLegacySidebarCacheFile = sqliteDatastore == nil
        case .missing:
            break
        case .corrupt(let error):
            let quarantinedURL = persistor.quarantineCorruptSidebarCacheFile(for: workspaceId)
            sidebarCacheStoreLogger.warning("Sidebar cache file corrupt, using defaults: \(error)")
            recoveryReporter?(
                .init(
                    store: .sidebarCache,
                    workspaceId: workspaceId,
                    recovery: quarantinedURL == nil ? .quarantineFailed : .quarantinedAndReset,
                    quarantinedFilename: quarantinedURL?.lastPathComponent
                )
            )
        }
    }

    private func restoreFromLegacyFilesAsync(
        workspaceId: UUID,
        legacyImportDecision: WorkspaceLocalSQLiteLegacyImportDecision
    ) async {
        restoreFromLegacyFiles(workspaceId: workspaceId, legacyImportDecision: legacyImportDecision)
        guard legacyImportDecision.allowsLegacyImport, persistor.hasLegacySidebarCacheFile(for: workspaceId) else {
            return
        }
        canArchiveLegacySidebarCacheFile = await materializeSQLiteIfNeeded(for: workspaceId)
    }

    func flush(for workspaceId: UUID) throws {
        guard sqliteDatastore == nil else {
            preconditionFailure("Use await flushAsync(for:) when SQLite datastore is enabled")
        }
        activeWorkspaceId = workspaceId
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        try persistLegacyJSONNow(for: workspaceId)
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
            if let sqliteDatastore {
                try await sqliteDatastore.saveSidebarState(
                    expandedGroups: atom.expandedGroups, workspaceId: workspaceId)
                return
            }
            try persistLegacyJSONNow(for: workspaceId)
        } catch {
            reportSaveFailed(workspaceId: workspaceId)
            throw error
        }
    }

    private func persistLegacyJSONNow(for workspaceId: UUID) throws {
        guard persistor.ensureDirectory() else {
            throw CocoaError(.fileWriteUnknown)
        }
        try persistor.saveSidebarCache(
            .init(
                workspaceId: workspaceId,
                expandedGroups: atom.expandedGroups
            )
        )
    }

    private enum SQLiteRestoreOutcome {
        case restored
        case missing(WorkspaceLocalSQLiteLegacyImportDecision, recoveryEvents: [PersistenceRecoveryEvent])
        case unavailable(recoveryEvents: [PersistenceRecoveryEvent])
    }

    private func restoreFromSQLite(
        for workspaceId: UUID,
        sqliteDatastore: WorkspaceSQLiteDatastore
    ) async -> SQLiteRestoreOutcome {
        switch await sqliteDatastore.loadSidebarState(workspaceId: workspaceId) {
        case .loaded(let payload):
            guard let expandedGroups = payload.expandedGroups else {
                return .missing(payload.legacyDecision, recoveryEvents: payload.recoveryEvents)
            }
            isRestoringState = true
            atom.setExpandedGroups(expandedGroups)
            isRestoringState = false
            return .restored
        case .unavailable(let failure, let recoveryEvents):
            isRestoringState = false
            sidebarCacheStoreLogger.warning("Sidebar cache SQLite restore failed: \(failure.description)")
            return .unavailable(recoveryEvents: recoveryEvents)
        }
    }

    private func materializeSQLiteIfNeeded(for workspaceId: UUID) async -> Bool {
        guard sqliteDatastore != nil else { return true }
        do {
            try await persistNow(for: workspaceId)
            return true
        } catch {
            sidebarCacheStoreLogger.warning(
                "Sidebar cache legacy import materialization failed: \(error.localizedDescription)"
            )
            return false
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
