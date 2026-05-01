import Foundation
import Observation
import os.log

private let uiStateStoreLogger = Logger(subsystem: "com.agentstudio", category: "UIStateStore")

@MainActor
final class UIStateStore {
    private let atom: UIStateAtom
    private let editorChooserAtom: EditorChooserAtom
    private let persistor: WorkspacePersistor
    private let persistDebounceDuration: Duration
    private let clock: any Clock<Duration>
    private let recoveryReporter: PersistenceRecoveryReporter?
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingUIState = false
    private var isRestoringState = false
    private var activeWorkspaceId: UUID?

    init(
        atom: UIStateAtom,
        editorChooserAtom: EditorChooserAtom,
        persistor: WorkspacePersistor = WorkspacePersistor(),
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: any Clock<Duration> = ContinuousClock(),
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.atom = atom
        self.editorChooserAtom = editorChooserAtom
        self.persistor = persistor
        self.persistDebounceDuration = persistDebounceDuration
        self.clock = clock
        self.recoveryReporter = recoveryReporter
        observeUIState()
    }

    func restore(for workspaceId: UUID) {
        activeWorkspaceId = workspaceId
        switch persistor.loadUI(for: workspaceId) {
        case .loaded(let state):
            isRestoringState = true
            atom.hydrate(
                filterText: state.filterText,
                isFilterVisible: state.isFilterVisible,
                showMinimizedBars: state.showMinimizedBars,
                sidebarCollapsed: state.sidebarCollapsed,
                sidebarSurface: state.sidebarSurface
            )
            editorChooserAtom.hydrate(bookmarkedEditorId: state.editorChooserState.bookmarkedEditorId)
            isRestoringState = false
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
            _ = atom.showMinimizedBars
            _ = atom.sidebarCollapsed
            _ = atom.sidebarSurface
            _ = editorChooserAtom.state.bookmarkedEditorId
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                // UIStateAtom and EditorChooserAtom are @MainActor; this traps if that ownership changes.
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
        guard persistor.ensureDirectory() else {
            throw CocoaError(.fileWriteUnknown)
        }
        try persistor.saveUI(
            .init(
                workspaceId: workspaceId,
                filterText: atom.filterText,
                isFilterVisible: atom.isFilterVisible,
                showMinimizedBars: atom.showMinimizedBars,
                sidebarCollapsed: atom.sidebarCollapsed,
                sidebarSurface: atom.sidebarSurface,
                editorChooserState: .init(bookmarkedEditorId: editorChooserAtom.state.bookmarkedEditorId)
            )
        )
    }
}
