import Foundation
import os.log

private let sidebarCacheStoreLogger = Logger(subsystem: "com.agentstudio", category: "SidebarCacheStore")

@MainActor
final class SidebarCacheStore {
    private let atom: SidebarCacheAtom
    private let persistor: WorkspacePersistor
    private let recoveryReporter: PersistenceRecoveryReporter?

    init(
        atom: SidebarCacheAtom,
        persistor: WorkspacePersistor = WorkspacePersistor(),
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.atom = atom
        self.persistor = persistor
        self.recoveryReporter = recoveryReporter
    }

    func restore(for workspaceId: UUID) {
        switch persistor.loadSidebarCache(for: workspaceId) {
        case .loaded(let state):
            atom.hydrate(
                expandedGroups: state.expandedGroups,
                checkoutColors: state.checkoutColors,
                collapsedInboxGroups: state.collapsedInboxGroups
            )
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
        guard persistor.ensureDirectory() else {
            throw CocoaError(.fileWriteUnknown)
        }
        try persistor.saveSidebarCache(
            .init(
                workspaceId: workspaceId,
                expandedGroups: atom.expandedGroups,
                checkoutColors: atom.checkoutColors,
                collapsedInboxGroups: atom.collapsedInboxGroups
            )
        )
    }
}
