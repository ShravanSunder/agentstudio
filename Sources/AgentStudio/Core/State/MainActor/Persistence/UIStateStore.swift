import Foundation
import os.log

private let uiStateStoreLogger = Logger(subsystem: "com.agentstudio", category: "UIStateStore")

@MainActor
final class UIStateStore {
    private let atom: UIStateAtom
    private let persistor: WorkspacePersistor
    private let recoveryReporter: PersistenceRecoveryReporter?

    init(
        atom: UIStateAtom,
        persistor: WorkspacePersistor = WorkspacePersistor(),
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.atom = atom
        self.persistor = persistor
        self.recoveryReporter = recoveryReporter
    }

    func restore(for workspaceId: UUID) {
        switch persistor.loadUI(for: workspaceId) {
        case .loaded(let state):
            atom.hydrate(
                filterText: state.filterText,
                isFilterVisible: state.isFilterVisible,
                showMinimizedBars: state.showMinimizedBars,
                sidebarCollapsed: state.sidebarCollapsed,
                sidebarSurface: state.sidebarSurface,
                editorChooserState: .init(
                    openForPaneId: nil,
                    bookmarkedEditorId: state.editorChooserState.bookmarkedEditorId
                )
            )
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
                editorChooserState: .init(bookmarkedEditorId: atom.editorChooserState.bookmarkedEditorId)
            )
        )
    }
}
