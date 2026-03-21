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
    static func shouldStartHiddenRestore(
        policy: BackgroundRestorePolicy,
        hasExistingSession: Bool
    ) -> Bool {
        switch policy {
        case .off:
            return false
        case .existingSessionsOnly:
            return hasExistingSession
        case .allTerminalPanes:
            return true
        }
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
        guard let store, let activeTab = store.activeTab else { return false }
        if activeTab.activePaneId == paneId.uuid {
            return true
        }

        return expandedDrawerActivePaneIds(in: store, activeTab: activeTab).contains(paneId.uuid)
    }

    private func isVisible(_ paneId: PaneId) -> Bool {
        guard let store, let activeTab = store.activeTab else { return false }

        if let zoomedPaneId = activeTab.zoomedPaneId {
            return zoomedPaneId == paneId.uuid
        }

        if activeTab.paneIds.contains(paneId.uuid) {
            return !activeTab.minimizedPaneIds.contains(paneId.uuid)
        }

        guard
            let pane = store.pane(paneId.uuid),
            let parentPaneId = pane.parentPaneId,
            activeTab.paneIds.contains(parentPaneId),
            let drawer = store.pane(parentPaneId)?.drawer,
            drawer.isExpanded,
            drawer.layout.contains(paneId.uuid),
            !drawer.minimizedPaneIds.contains(paneId.uuid)
        else {
            return false
        }

        return true
    }

    private func expandedDrawerActivePaneIds(in store: WorkspaceStore, activeTab: Tab) -> Set<UUID> {
        Set(
            activeTab.paneIds.compactMap { paneId in
                guard let drawer = store.pane(paneId)?.drawer, drawer.isExpanded else {
                    return nil
                }
                return drawer.activePaneId
            }
        )
    }
}
