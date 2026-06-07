import Foundation
import Observation
import os.log

private let sidebarCacheStoreLogger = Logger(subsystem: "com.agentstudio", category: "SidebarCacheStore")

@MainActor
final class SidebarCacheStore {
    private let atom: SidebarCacheState
    private let persistor: WorkspacePersistor
    private let sqliteBackend: WorkspaceLocalSQLiteStoreBackend?
    private let persistDebounceDuration: Duration
    private let clock: any Clock<Duration>
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
        sqliteBackend: WorkspaceLocalSQLiteStoreBackend? = nil,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: any Clock<Duration> = ContinuousClock(),
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.atom = atom
        self.persistor = persistor
        self.sqliteBackend = sqliteBackend
        self.persistDebounceDuration = persistDebounceDuration
        self.clock = clock
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
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        activeWorkspaceId = workspaceId
        canArchiveLegacySidebarCacheFile = true
        switch restoreFromSQLite(for: workspaceId) {
        case .restored:
            return
        case .missing:
            guard canImportLegacyExpandedGroups(for: workspaceId) else {
                atom.clear()
                canArchiveLegacySidebarCacheFile = false
                recoveryReporter?(
                    .init(store: .sidebarCache, workspaceId: workspaceId, recovery: .resetToDefaults)
                )
                return
            }
        case .unavailable:
            atom.clear()
            canArchiveLegacySidebarCacheFile = false
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
            canArchiveLegacySidebarCacheFile = materializeSQLiteIfNeeded(for: workspaceId)
        case .missing:
            break
        case .corrupt(let error):
            let quarantinedURL = persistor.quarantineCorruptSidebarCacheFile(for: workspaceId)
            sidebarCacheStoreLogger.warning("Sidebar cache file corrupt, using defaults: \(error)")
            recoveryReporter?(
                .init(
                    store: .sidebarCache,
                    workspaceId: workspaceId,
                    recovery: .quarantinedAndReset,
                    quarantinedFilename: quarantinedURL?.lastPathComponent
                )
            )
        }
    }

    func flush(for workspaceId: UUID) throws {
        activeWorkspaceId = workspaceId
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        try persistNow(for: workspaceId)
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
        debouncedSaveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.clock.sleep(for: self.persistDebounceDuration)
            guard !Task.isCancelled else { return }
            do {
                try self.persistNow(for: workspaceId)
            } catch {
                sidebarCacheStoreLogger.warning("Sidebar cache autosave failed: \(error.localizedDescription)")
            }
        }
    }

    private func persistNow(for workspaceId: UUID) throws {
        do {
            if let sqliteBackend {
                let repository = try sqliteBackend.repository(for: workspaceId)
                try repository.replaceExpandedGroups(atom.expandedGroups, updatedAt: Date())
                return
            }
            guard persistor.ensureDirectory() else {
                throw CocoaError(.fileWriteUnknown)
            }
            try persistor.saveSidebarCache(
                .init(
                    workspaceId: workspaceId,
                    expandedGroups: atom.expandedGroups,
                    checkoutColors: [:]
                )
            )
        } catch {
            reportSaveFailed(workspaceId: workspaceId)
            throw error
        }
    }

    private func restoreFromSQLite(for workspaceId: UUID) -> LocalSQLiteRestoreOutcome {
        guard let sqliteBackend else { return .missing }
        do {
            let repository = try sqliteBackend.restoreRepository(for: workspaceId)
            guard try repository.hasExpandedGroupsState() else { return .missing }
            isRestoringState = true
            atom.setExpandedGroups(try repository.fetchExpandedGroups())
            isRestoringState = false
            return .restored
        } catch {
            isRestoringState = false
            sidebarCacheStoreLogger.warning("Sidebar cache SQLite restore failed: \(error.localizedDescription)")
            return .unavailable(error)
        }
    }

    private func canImportLegacyExpandedGroups(for workspaceId: UUID) -> Bool {
        guard let sqliteBackend else { return true }
        do {
            return try sqliteBackend.allowsLegacyImport(for: workspaceId, lane: .local)
        } catch {
            sidebarCacheStoreLogger.warning(
                "Sidebar cache legacy import permission check failed: \(error.localizedDescription)"
            )
            return false
        }
    }

    private func materializeSQLiteIfNeeded(for workspaceId: UUID) -> Bool {
        guard sqliteBackend != nil else { return true }
        do {
            try persistNow(for: workspaceId)
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
}
