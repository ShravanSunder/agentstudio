import Foundation
import Observation
import os.log

private let uiStateStoreLogger = Logger(subsystem: "com.agentstudio", category: "UIStateStore")

@MainActor
final class UIStateStore {
    private let atom: WorkspaceSidebarState
    private let persistor: WorkspacePersistor
    private let sqliteDatastore: WorkspaceSQLiteDatastore?
    private let persistDebounceDuration: Duration
    private let clock: any Clock<Duration>
    private let recoveryReporter: PersistenceRecoveryReporter?
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingUIState = false
    private var isRestoringState = false
    private var activeWorkspaceId: UUID?
    private(set) var canArchiveLegacyUIFile = true

    var isAutosaveObservationActive: Bool {
        isObservingUIState
    }

    init(
        atom: WorkspaceSidebarState,
        editorChooserState _: EditorChooserState? = nil,
        persistor: WorkspacePersistor = WorkspacePersistor(),
        sqliteDatastore: WorkspaceSQLiteDatastore? = nil,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: any Clock<Duration> = ContinuousClock(),
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.atom = atom
        self.persistor = persistor
        self.sqliteDatastore = sqliteDatastore
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
        guard sqliteDatastore == nil else {
            assertionFailure("Use await restoreAsync(for:) when SQLite datastore is enabled")
            return
        }
        restoreFromLegacyFiles(workspaceId: workspaceId, legacyImportDecision: .allowImport)
    }

    func restoreAsync(for workspaceId: UUID) async {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        activeWorkspaceId = workspaceId
        canArchiveLegacyUIFile = true
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
                canArchiveLegacyUIFile = false
                recoveryReporter?(
                    .init(store: .uiState, workspaceId: workspaceId, recovery: .resetToDefaults)
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
            canArchiveLegacyUIFile = !persistor.hasLegacyUIFile(for: workspaceId)
            recoveryReporter?(
                .init(store: .uiState, workspaceId: workspaceId, recovery: .resetToDefaults)
            )
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
            canArchiveLegacyUIFile = sqliteDatastore == nil
        case .missing:
            break
        case .corrupt(let error):
            let quarantinedURL = persistor.quarantineCorruptUIFile(for: workspaceId)
            uiStateStoreLogger.warning("UI state file corrupt, using defaults: \(error)")
            recoveryReporter?(
                .init(
                    store: .uiState,
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
        guard legacyImportDecision.allowsLegacyImport, persistor.hasLegacyUIFile(for: workspaceId) else {
            return
        }
        canArchiveLegacyUIFile = await materializeSQLiteIfNeeded(for: workspaceId)
    }

    func flush(for workspaceId: UUID) throws {
        guard sqliteDatastore == nil else {
            assertionFailure("Use await flushAsync(for:) when SQLite datastore is enabled")
            throw CocoaError(.fileWriteUnknown)
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
                try await self.persistNow(for: workspaceId)
            } catch {
                uiStateStoreLogger.warning("UI state autosave failed: \(error.localizedDescription)")
            }
        }
    }

    private func persistNow(for workspaceId: UUID) async throws {
        do {
            if let sqliteDatastore {
                try await sqliteDatastore.saveUIState(currentSidebarStateRecord(), workspaceId: workspaceId)
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
        try persistor.saveUI(
            .init(
                workspaceId: workspaceId,
                filterText: atom.filterText,
                isFilterVisible: atom.isFilterVisible,
                sidebarCollapsed: atom.sidebarCollapsed,
                sidebarSurface: atom.sidebarSurface
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
        switch await sqliteDatastore.loadUIState(workspaceId: workspaceId) {
        case .loaded(let payload):
            guard let state = payload.state else {
                return .missing(payload.legacyDecision, recoveryEvents: payload.recoveryEvents)
            }
            isRestoringState = true
            atom.hydrate(
                filterText: state.filterText,
                isFilterVisible: state.isFilterVisible,
                sidebarCollapsed: state.sidebarCollapsed,
                sidebarSurface: state.sidebarSurface
            )
            isRestoringState = false
            return .restored
        case .unavailable(let failure, let recoveryEvents):
            isRestoringState = false
            uiStateStoreLogger.warning("UI state SQLite restore failed: \(failure.description)")
            return .unavailable(recoveryEvents: recoveryEvents)
        }
    }

    private func materializeSQLiteIfNeeded(for workspaceId: UUID) async -> Bool {
        guard sqliteDatastore != nil else { return true }
        do {
            try await persistNow(for: workspaceId)
            return true
        } catch {
            uiStateStoreLogger.warning(
                "UI state legacy import materialization failed: \(error.localizedDescription)"
            )
            return false
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
        recoveryEvents.forEach { recoveryReporter?($0) }
    }
}
