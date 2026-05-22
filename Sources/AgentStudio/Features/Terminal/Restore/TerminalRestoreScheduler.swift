import Foundation

struct TerminalRestoreScheduler {
    @MainActor
    static func order(
        _ paneIds: [PaneId],
        resolver: some TerminalRestoreVisibilityResolving
    ) -> [PaneId] {
        paneIds.enumerated().sorted { lhs, rhs in
            let lhsTier = resolver.tier(for: lhs.element)
            let rhsTier = resolver.tier(for: rhs.element)

            if lhsTier != rhsTier {
                return lhsTier < rhsTier
            }

            let lhsIsActive = resolver.isActive(lhs.element)
            let rhsIsActive = resolver.isActive(rhs.element)
            if lhsTier == .p0Visible, lhsIsActive != rhsIsActive {
                return lhsIsActive
            }

            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    @MainActor
    static func shouldStartHiddenRestore(hasExistingSession: Bool) -> Bool {
        hasExistingSession
    }
}

@MainActor
protocol TerminalRestoreVisibilityResolving: VisibilityTierResolver {
    func isActive(_ paneId: PaneId) -> Bool
}

@MainActor
final class StoreVisibilityTierResolver: TerminalRestoreVisibilityResolving {
    private weak var store: WorkspaceStore?

    init(store: WorkspaceStore) {
        self.store = store
    }

    func tier(for paneId: PaneId) -> VisibilityTier {
        isVisible(paneId) ? .p0Visible : .p1Hidden
    }

    func isActive(_ paneId: PaneId) -> Bool {
        guard let store, let activeTab = store.tabLayoutAtom.activeTab else { return false }
        if activeTab.activePaneId == paneId.uuid {
            return true
        }

        return expandedDrawerActivePaneIds(in: store, activeTab: activeTab).contains(paneId.uuid)
    }

    private func isVisible(_ paneId: PaneId) -> Bool {
        guard let store, let activeTab = store.tabLayoutAtom.activeTab else { return false }

        if let zoomedPaneId = activeTab.zoomedPaneId {
            return zoomedPaneId == paneId.uuid
        }

        if activeTab.activePaneIds.contains(paneId.uuid) {
            return !activeTab.activeMinimizedPaneIds.contains(paneId.uuid)
        }

        guard
            let pane = store.paneAtom.pane(paneId.uuid),
            let parentPaneId = pane.parentPaneId,
            activeTab.activePaneIds.contains(parentPaneId),
            let drawer = store.paneAtom.pane(parentPaneId)?.drawer,
            drawer.isExpanded,
            let drawerView = drawerView(forParent: parentPaneId, in: store),
            drawerView.layout.contains(paneId.uuid),
            !drawerView.minimizedPaneIds.contains(paneId.uuid)
        else {
            return false
        }

        return true
    }

    private func expandedDrawerActivePaneIds(in store: WorkspaceStore, activeTab: Tab) -> Set<UUID> {
        Set(
            activeTab.activePaneIds.compactMap { paneId in
                guard let drawer = store.paneAtom.pane(paneId)?.drawer, drawer.isExpanded else {
                    return nil
                }
                return drawerView(forParent: paneId, in: store)?.activeChildId
            }
        )
    }

    private func drawerView(forParent parentPaneId: UUID, in store: WorkspaceStore) -> DrawerView? {
        guard
            let tab = store.tabLayoutAtom.tabContaining(paneId: parentPaneId),
            let drawer = store.paneAtom.pane(parentPaneId)?.drawer
        else { return nil }

        return tab.activeArrangement.drawerViews[drawer.drawerId]
    }
}
