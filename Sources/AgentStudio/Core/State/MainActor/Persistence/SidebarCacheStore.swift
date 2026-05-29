import Foundation
import Observation
import os.log

private let sidebarCacheStoreLogger = Logger(subsystem: "com.agentstudio", category: "SidebarCacheStore")

@MainActor
final class SidebarCacheStore {
    private let atom: SidebarCacheAtom
    private let persistor: WorkspacePersistor
    private let persistDebounceDuration: Duration
    private let clock: any Clock<Duration>
    private let recoveryReporter: PersistenceRecoveryReporter?
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingCacheState = false
    private var isRestoringState = false
    private var activeWorkspaceId: UUID?

    var isAutosaveObservationActive: Bool {
        isObservingCacheState
    }

    init(
        atom: SidebarCacheAtom,
        persistor: WorkspacePersistor = WorkspacePersistor(),
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: any Clock<Duration> = ContinuousClock(),
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.atom = atom
        self.persistor = persistor
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
        switch persistor.loadSidebarCache(for: workspaceId) {
        case .loaded(let state):
            isRestoringState = true
            atom.hydrate(
                expandedGroups: state.expandedGroups,
                checkoutColors: state.checkoutColors
            )
            isRestoringState = false
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
            _ = atom.checkoutColors
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                // SidebarCacheAtom is @MainActor; this traps if that ownership changes.
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
            guard persistor.ensureDirectory() else {
                throw CocoaError(.fileWriteUnknown)
            }
            try persistor.saveSidebarCache(
                .init(
                    workspaceId: workspaceId,
                    expandedGroups: atom.expandedGroups,
                    checkoutColors: atom.checkoutColors
                )
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
}
