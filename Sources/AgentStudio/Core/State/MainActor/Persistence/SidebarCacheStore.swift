import Foundation
import os.log

private let sidebarCacheStoreLogger = Logger(subsystem: "com.agentstudio", category: "SidebarCacheStore")

@MainActor
final class SidebarCacheStore {
    private let atom: SidebarCacheAtom
    private let persistor: WorkspacePersistor

    init(
        atom: SidebarCacheAtom,
        persistor: WorkspacePersistor = WorkspacePersistor()
    ) {
        self.atom = atom
        self.persistor = persistor
    }

    func restore(for workspaceId: UUID) {
        switch persistor.loadSidebarCache(for: workspaceId) {
        case .loaded(let state):
            let expandedGroups: Set<SidebarGroupKey> = Set(
                state.expandedGroups.map { SidebarGroupKey($0) }
            )
            let checkoutColors: [SidebarCheckoutColorKey: String] = Dictionary(
                uniqueKeysWithValues: state.checkoutColors.map { key, value in
                    (SidebarCheckoutColorKey(key), value)
                }
            )
            let collapsedInboxGroups: Set<InboxNotificationGroupKey> = Set(
                state.collapsedInboxGroups.map { InboxNotificationGroupKey($0) }
            )
            atom.hydrate(
                expandedGroups: expandedGroups,
                checkoutColors: checkoutColors,
                collapsedInboxGroups: collapsedInboxGroups
            )
        case .missing:
            break
        case .corrupt(let error):
            _ = persistor.quarantineCorruptSidebarCacheFile(for: workspaceId)
            sidebarCacheStoreLogger.warning("Sidebar cache file corrupt, using defaults: \(error)")
        }
    }

    func flush(for workspaceId: UUID) throws {
        guard persistor.ensureDirectory() else {
            throw CocoaError(.fileWriteUnknown)
        }
        try persistor.saveSidebarCache(
            .init(
                workspaceId: workspaceId,
                expandedGroups: Set(atom.expandedGroups.map(\.rawValue)),
                checkoutColors: Dictionary(
                    uniqueKeysWithValues: atom.checkoutColors.map { key, value in
                        (key.rawValue, value)
                    }
                ),
                collapsedInboxGroups: Set(atom.collapsedInboxGroups.map(\.rawValue))
            )
        )
    }
}
