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
        guard let activeLayout = activeLayout(forTab: tabId) else {
            return []
        }
        return visiblePaneIds(
            layoutPaneIds: activeLayout.paneIds,
            minimizedPaneIds: activeMinimizedPaneIds(forTab: tabId)
        )
    }

    /// The active arrangement projected for rendering. Canonical layouts retain
    /// backgrounded pane references so their arrangement survives a restart;
    /// rendering must not give those deferred panes a visual slot.
    package func activeLayout(forTab tabId: UUID) -> Layout? {
        guard let canonicalLayout = tabLayoutAtom.tab(tabId)?.activeArrangement.layout else {
            workspaceArrangementViewLogger.warning("activeLayout: tab \(tabId) not found")
            return nil
        }

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
        guard let activeArrangement = tabLayoutAtom.tab(tabId)?.activeArrangement else {
            return nil
        }
        return paneAtom.activeResidencyPaneId(
            preferred: activeArrangement.activePaneId,
            in: activeArrangement.layout.paneIds
        )
    }

    package func activeMinimizedPaneIds(forTab tabId: UUID) -> Set<UUID> {
        let minimizedPaneIds = tabLayoutAtom.tab(tabId)?.activeArrangement.minimizedPaneIds ?? []
        guard let activeLayout = activeLayout(forTab: tabId) else { return [] }
        return minimizedPaneIds.intersection(Set(activeLayout.paneIds))
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
}
