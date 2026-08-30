import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

package struct TerminalRestoreScheduler {
    @MainActor
    package static func order(
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
package protocol TerminalRestoreVisibilityResolving: VisibilityTierResolver {
    func isActive(_ paneId: PaneId) -> Bool
}

@MainActor
package final class StoreVisibilityTierResolver: TerminalRestoreVisibilityResolving {
    private weak var store: WorkspaceStore?

    package init(store: WorkspaceStore) {
        self.store = store
    }

    package func tier(for paneId: PaneId) -> VisibilityTier {
        guard hasActiveResidency(paneId) else { return .p1Hidden }
        return isVisible(paneId) ? .p0Visible : .p1Hidden
    }

    package func isActive(_ paneId: PaneId) -> Bool {
        guard hasActiveResidency(paneId) else { return false }
        guard let store, let activeTab = store.tabLayoutAtom.activeTab else { return false }
        if activeTab.activePaneId == paneId.uuid {
            return true
        }

        return expandedDrawerActivePaneIds(in: store, activeTab: activeTab).contains(paneId.uuid)
    }

    private func isVisible(_ paneId: PaneId) -> Bool {
        guard let store, let activeTab = store.tabLayoutAtom.activeTab else { return false }

        if let sourcePaneId = store.panePresentationAtom.zoomPresentation(forTab: activeTab.id)?.sourcePaneId {
            return sourcePaneId == paneId.uuid
        }

        if activeTab.activePaneIds.contains(paneId.uuid) {
            return !activeTab.activeMinimizedPaneIds.contains(paneId.uuid)
        }

        guard
            let paneFacts = store.paneAtom.graphAtom.paneStructuralFacts(paneId.uuid),
            let parentPaneId = paneFacts.parentPaneID,
            activeTab.activePaneIds.contains(parentPaneId),
            !activeTab.activeMinimizedPaneIds.contains(parentPaneId),
            store.paneAtom.isDrawerExpanded(for: parentPaneId),
            let drawerView = drawerView(forParent: parentPaneId, in: store),
            drawerView.layout.contains(paneId.uuid),
            !drawerView.minimizedPaneIds.contains(paneId.uuid)
        else {
            return false
        }

        return true
    }

    private func hasActiveResidency(_ paneId: PaneId) -> Bool {
        guard let store,
            let facts = store.paneAtom.graphAtom.paneStructuralFacts(paneId.uuid)
        else { return false }
        return facts.residency == .active
    }

    private func expandedDrawerActivePaneIds(in store: WorkspaceStore, activeTab: Tab) -> Set<UUID> {
        Set(
            activeTab.activePaneIds.compactMap { paneId in
                guard store.paneAtom.isDrawerExpanded(for: paneId) else {
                    return nil
                }
                return drawerView(forParent: paneId, in: store)?.activeChildId
            }
        )
    }

    private func drawerView(forParent parentPaneId: UUID, in store: WorkspaceStore) -> DrawerView? {
        guard
            let tab = store.tabLayoutAtom.tabContaining(paneId: parentPaneId),
            let drawerID = store.paneAtom.graphAtom.paneStructuralFacts(parentPaneId)?.ownedDrawerID
        else { return nil }

        return tab.activeArrangement.drawerViews[drawerID]
    }
}
