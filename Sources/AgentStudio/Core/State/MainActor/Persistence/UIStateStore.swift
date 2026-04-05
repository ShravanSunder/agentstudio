import Foundation
import os.log

private let uiStateStoreLogger = Logger(subsystem: "com.agentstudio", category: "UIStateStore")

@MainActor
final class UIStateStore {
    private let atom: UIStateAtom
    private let persistor: WorkspacePersistor

    init(
        atom: UIStateAtom,
        persistor: WorkspacePersistor = WorkspacePersistor()
    ) {
        self.atom = atom
        self.persistor = persistor
    }

    func restore(for workspaceId: UUID) {
        switch persistor.loadUI(for: workspaceId) {
        case .loaded(let state):
            atom.hydrate(
                expandedGroups: state.expandedGroups,
                checkoutColors: state.checkoutColors,
                filterText: state.filterText,
                isFilterVisible: state.isFilterVisible
            )
        case .missing:
            break
        case .corrupt(let error):
            uiStateStoreLogger.warning("UI state file corrupt, using defaults: \(error)")
        }
    }

    func flush(for workspaceId: UUID) throws {
        try persistor.saveUI(
            .init(
                workspaceId: workspaceId,
                expandedGroups: atom.expandedGroups,
                checkoutColors: atom.checkoutColors,
                filterText: atom.filterText,
                isFilterVisible: atom.isFilterVisible
            )
        )
    }
}
