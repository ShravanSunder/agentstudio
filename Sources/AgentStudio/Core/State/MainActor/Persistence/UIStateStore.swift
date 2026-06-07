import Foundation
import Observation
import os.log

private let uiStateStoreLogger = Logger(subsystem: "com.agentstudio", category: "UIStateStore")

@MainActor
final class UIStateStore {
    private let atom: WorkspaceSidebarState
    private let persistor: WorkspacePersistor
    private let sqliteBackend: WorkspaceLocalSQLiteStoreBackend?
    private let persistDebounceDuration: Duration
    private let clock: any Clock<Duration>
    private let recoveryReporter: PersistenceRecoveryReporter?
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingUIState = false
    private var isRestoringState = false
    private var activeWorkspaceId: UUID?

    var isAutosaveObservationActive: Bool {
        isObservingUIState
    }

    init(
        atom: WorkspaceSidebarState,
        editorChooserState _: EditorChooserState? = nil,
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
        observeUIState()
    }

    func restore(for workspaceId: UUID) {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        activeWorkspaceId = workspaceId
        if restoreFromSQLite(for: workspaceId) {
            return
        }
        switch persistor.loadUI(for: workspaceId) {
        case .loaded(let state):
            isRestoringState = true
            atom.hydrate(
                filterText: state.filterText,
                isFilterVisible: state.isFilterVisible,
                sidebarCollapsed: state.sidebarCollapsed,
                sidebarSurface: state.sidebarSurface
            )
            isRestoringState = false
            materializeSQLiteIfNeeded(for: workspaceId)
        case .missing:
            break
        case .corrupt(let error):
            let quarantinedURL = persistor.quarantineCorruptUIFile(for: workspaceId)
            uiStateStoreLogger.warning("UI state file corrupt, using defaults: \(error)")
            recoveryReporter?(
                .init(
                    store: .uiState,
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

    private func observeUIState() {
        guard !isObservingUIState else { return }
        isObservingUIState = true
        withObservationTracking {
            _ = atom.filterText
            _ = atom.isFilterVisible
            _ = atom.sidebarCollapsed
            _ = atom.sidebarSurface
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                // WorkspaceSidebarState is @MainActor; this traps if that ownership changes.
                guard let self else { return }
                let shouldIgnore = self.isRestoringState
                self.isObservingUIState = false
                self.observeUIState()
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
                uiStateStoreLogger.warning("UI state autosave failed: \(error.localizedDescription)")
            }
        }
    }

    private func persistNow(for workspaceId: UUID) throws {
        do {
            if let sqliteBackend {
                let repository = try sqliteBackend.repository(for: workspaceId)
                try repository.replaceSidebarState(
                    .init(
                        filterText: atom.filterText,
                        isFilterVisible: atom.isFilterVisible,
                        sidebarCollapsed: atom.sidebarCollapsed,
                        sidebarSurface: atom.sidebarSurface
                    ),
                    updatedAt: Date()
                )
                return
            }
            guard persistor.ensureDirectory() else {
                throw CocoaError(.fileWriteUnknown)
            }
            try persistor.saveUI(
                .init(
                    workspaceId: workspaceId,
                    filterText: atom.filterText,
                    isFilterVisible: atom.isFilterVisible,
                    sidebarCollapsed: atom.sidebarCollapsed,
                    sidebarSurface: atom.sidebarSurface
                )
            )
        } catch {
            reportSaveFailed(workspaceId: workspaceId)
            throw error
        }
    }

    private func restoreFromSQLite(for workspaceId: UUID) -> Bool {
        guard let sqliteBackend else { return false }
        do {
            let repository = try sqliteBackend.repository(for: workspaceId)
            guard try repository.hasSidebarState(),
                let state = try repository.fetchSidebarState()
            else {
                return false
            }
            isRestoringState = true
            atom.hydrate(
                filterText: state.filterText,
                isFilterVisible: state.isFilterVisible,
                sidebarCollapsed: state.sidebarCollapsed,
                sidebarSurface: state.sidebarSurface
            )
            isRestoringState = false
            return true
        } catch {
            uiStateStoreLogger.warning("UI state SQLite restore failed: \(error.localizedDescription)")
            return false
        }
    }

    private func materializeSQLiteIfNeeded(for workspaceId: UUID) {
        guard sqliteBackend != nil else { return }
        do {
            try persistNow(for: workspaceId)
        } catch {
            uiStateStoreLogger.warning(
                "UI state legacy import materialization failed: \(error.localizedDescription)"
            )
        }
    }

    private func reportSaveFailed(workspaceId: UUID) {
        recoveryReporter?(
            .init(store: .uiState, workspaceId: workspaceId, recovery: .saveFailed)
        )
    }
}
