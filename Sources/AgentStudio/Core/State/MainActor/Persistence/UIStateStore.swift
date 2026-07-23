import Foundation
import Observation
import os.log

private let uiStateStoreLogger = Logger(subsystem: "com.agentstudio", category: "UIStateStore")

@MainActor
final class UIStateStore {
    private let atom: WorkspaceSidebarState
    private let sqliteDatastore: WorkspaceSQLiteDatastore
    private let persistDebounceDuration: Duration
    private let delay: AsyncDelay
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
        observeUIState()
    }

    func restoreAsync(for workspaceId: UUID) async {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        activeWorkspaceId = workspaceId
        switch await sqliteDatastore.loadUIState(workspaceContextId: workspaceId) {
        case .loaded(let payload):
            isRestoringState = true
            if let state = payload.state {
                atom.hydrate(
                    filterText: state.filterText,
                    isFilterVisible: state.isFilterVisible,
                    sidebarCollapsed: state.sidebarCollapsed,
                    sidebarSurface: state.sidebarSurface
                )
            } else {
                atom.clear()
            }
            isRestoringState = false
            reportRecoveryEvents(payload.recoveryEvents)
        case .unavailable(let failure, let recoveryEvents):
            isRestoringState = false
            atom.clear()
            reportRecoveryEvents(recoveryEvents)
            uiStateStoreLogger.warning("UI state SQLite restore failed: \(failure.description)")
            recoveryReporter?(
                .init(
                    store: .uiState,
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
        let delay = self.delay
        let persistDebounceDuration = self.persistDebounceDuration
        debouncedSaveTask = Task { @MainActor [weak self, delay, persistDebounceDuration, workspaceId] in
            try? await delay.wait(persistDebounceDuration)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            do {
                try await self.persistNow(for: workspaceId)
            } catch {
                uiStateStoreLogger.warning("UI state autosave failed: \(error.localizedDescription)")
            }
        }
    }

    private func persistNow(for workspaceId: UUID) async throws {
        do {
            try await sqliteDatastore.saveUIState(
                currentSidebarStateRecord(),
                workspaceContextId: workspaceId
            )
        } catch {
            reportSaveFailed(workspaceId: workspaceId)
            throw error
        }
    }

    private func reportSaveFailed(workspaceId: UUID) {
        recoveryReporter?(
            .init(store: .uiState, workspaceId: workspaceId, recovery: .saveFailed)
        )
    }

    private func currentSidebarStateRecord() -> WorkspaceLocalRepository.SidebarStateRecord {
        .init(
            filterText: atom.filterText,
            isFilterVisible: atom.isFilterVisible,
            sidebarCollapsed: atom.sidebarCollapsed,
            sidebarSurface: atom.sidebarSurface
        )
    }

    private func reportRecoveryEvents(_ recoveryEvents: [PersistenceRecoveryEvent]) {
        for recoveryEvent in recoveryEvents {
            recoveryReporter?(recoveryEvent)
        }
    }
}
