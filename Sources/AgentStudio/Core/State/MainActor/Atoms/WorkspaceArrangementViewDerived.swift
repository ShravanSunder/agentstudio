import Foundation
import os.log

private let workspaceArrangementViewLogger = Logger(
    subsystem: "com.agentstudio",
    category: "WorkspaceArrangementViewDerived"
)

@MainActor
package struct WorkspaceArrangementViewDerived {
    let tabLayoutAtom: WorkspaceTabLayoutAtom
    let paneAtom: WorkspacePaneAtom
    let managementLayerAtom: ManagementLayerAtom

    package init(
        tabLayoutAtom: WorkspaceTabLayoutAtom,
        paneAtom: WorkspacePaneAtom,
        managementLayerAtom: ManagementLayerAtom
    ) {
        self.tabLayoutAtom = tabLayoutAtom
        self.paneAtom = paneAtom
        self.managementLayerAtom = managementLayerAtom
    }

    package func activeVisiblePaneIds(forTab tabId: UUID) -> [UUID] {
        guard let tab = resolvedTab(forTab: tabId, logsMissing: true) else {
            return []
        }
        return activeVisiblePaneIds(forTab: tab)
    }

    package func activeVisiblePaneIds(forTab tab: Tab) -> [UUID] {
        guard let activeLayout = activeLayout(forTab: tab) else {
            return []
        }
        let minimizedPaneIds = activeMinimizedPaneIds(
            forTab: tab,
            activeLayout: activeLayout
        )
        return activeVisiblePaneIds(
            activeLayout: activeLayout,
            minimizedPaneIds: minimizedPaneIds
        )
    }

    package func activeVisiblePaneIds(
        activeLayout: Layout,
        minimizedPaneIds: Set<UUID>
    ) -> [UUID] {
        visiblePaneIds(
            layoutPaneIds: activeLayout.paneIds,
            minimizedPaneIds: minimizedPaneIds
        )
    }

    /// The active arrangement projected for rendering. Canonical layouts retain
    /// backgrounded pane references so their arrangement survives a restart;
    /// rendering must not give those deferred panes a visual slot.
    package func activeLayout(forTab tabId: UUID) -> Layout? {
        guard let tab = resolvedTab(forTab: tabId, logsMissing: true) else { return nil }
        return activeLayout(forTab: tab)
    }

    package func activeLayout(forTab tab: Tab) -> Layout? {
        let canonicalLayout = tab.activeArrangement.layout

        let activePaneIds = Set(paneAtom.activeResidencyPaneIds(in: canonicalLayout.paneIds))
        let activePaneIndexes = canonicalLayout.panes.indices.filter { index in
            activePaneIds.contains(canonicalLayout.panes[index].paneId)
        }
        let activePanes = activePaneIndexes.map { canonicalLayout.panes[$0] }
        let activeDividerIDs = activePaneIndexes.dropFirst().map { index in
            canonicalLayout.dividerIds[index - 1]
        }

        return Layout(panes: activePanes, dividerIds: activeDividerIDs)
    }

    package func drawerView(forParent parentPaneId: UUID) -> DrawerView? {
        guard
            let tab = tabLayoutAtom.tabContaining(paneId: parentPaneId),
            let paneFacts = paneAtom.graphAtom.paneStructuralFacts(parentPaneId),
            isActivePane(parentPaneId),
            let drawerID = paneFacts.ownedDrawerID
        else { return nil }
        if let drawerView = tab.activeArrangement.drawerViews[drawerID] {
            return drawerView
        }
        return paneFacts.ownedDrawerPaneIDs.isEmpty ? DrawerView() : nil
    }

    package func drawerVisiblePaneIds(forParent parentPaneId: UUID) -> [UUID] {
        guard
            tabLayoutAtom.tabContaining(paneId: parentPaneId) != nil,
            let drawerView = drawerView(forParent: parentPaneId)
        else { return [] }
        return visiblePaneIds(
            layoutPaneIds: paneAtom.activeResidencyPaneIds(in: drawerView.layout.paneIds),
            minimizedPaneIds: drawerView.minimizedPaneIds
        )
    }

    package func activePaneId(forTab tabId: UUID) -> UUID? {
        guard let tab = resolvedTab(forTab: tabId, logsMissing: false) else { return nil }
        return activePaneId(forTab: tab)
    }

    package func activePaneId(forTab tab: Tab) -> UUID? {
        let activeArrangement = tab.activeArrangement
        return paneAtom.activeResidencyPaneId(
            preferred: activeArrangement.activePaneId,
            in: activeArrangement.layout.paneIds
        )
    }

    package func activeMinimizedPaneIds(forTab tabId: UUID) -> Set<UUID> {
        guard let tab = resolvedTab(forTab: tabId, logsMissing: true) else { return [] }
        return activeMinimizedPaneIds(forTab: tab)
    }

    package func activeMinimizedPaneIds(forTab tab: Tab) -> Set<UUID> {
        guard let activeLayout = activeLayout(forTab: tab) else { return [] }
        return activeMinimizedPaneIds(forTab: tab, activeLayout: activeLayout)
    }

    private func visiblePaneIds(
        layoutPaneIds: [UUID],
        minimizedPaneIds: Set<UUID>
    ) -> [UUID] {
        guard !managementLayerAtom.isActive else { return layoutPaneIds }
        return layoutPaneIds.filter { !minimizedPaneIds.contains($0) }
    }

    private func isActivePane(_ paneID: UUID) -> Bool {
        paneAtom.graphAtom.paneStructuralFacts(paneID)?.residency.isActive == true
    }

    package func activeMinimizedPaneIds(
        forTab tab: Tab,
        activeLayout: Layout
    ) -> Set<UUID> {
        tab.activeArrangement.minimizedPaneIds.intersection(Set(activeLayout.paneIds))
    }

    private func resolvedTab(forTab tabId: UUID, logsMissing: Bool) -> Tab? {
        guard let tab = tabLayoutAtom.tab(tabId) else {
            if logsMissing {
                workspaceArrangementViewLogger.warning("activeLayout: tab \(tabId) not found")
            }
            return nil
        }
        return tab
    }
}
