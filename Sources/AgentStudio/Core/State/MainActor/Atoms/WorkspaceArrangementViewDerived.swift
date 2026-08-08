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
        guard let arrangement = tabLayoutAtom.tab(tabId)?.activeArrangement else {
            workspaceArrangementViewLogger.warning("activeVisiblePaneIds: tab \(tabId) not found")
            return []
        }
        return visiblePaneIds(
            layoutPaneIds: arrangement.layout.paneIds,
            minimizedPaneIds: arrangement.minimizedPaneIds
        )
    }

    package func drawerView(forParent parentPaneId: UUID) -> DrawerView? {
        guard
            let tab = tabLayoutAtom.tabContaining(paneId: parentPaneId),
            let paneFacts = paneAtom.graphAtom.paneStructuralFacts(parentPaneId),
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
            layoutPaneIds: drawerView.layout.paneIds,
            minimizedPaneIds: drawerView.minimizedPaneIds
        )
    }

    func activePaneId(forTab tabId: UUID) -> UUID? {
        tabLayoutAtom.tab(tabId)?.activeArrangement.activePaneId
    }

    func activeMinimizedPaneIds(forTab tabId: UUID) -> Set<UUID> {
        tabLayoutAtom.tab(tabId)?.activeArrangement.minimizedPaneIds ?? []
    }

    private func visiblePaneIds(
        layoutPaneIds: [UUID],
        minimizedPaneIds: Set<UUID>
    ) -> [UUID] {
        guard !managementLayerAtom.isActive else { return layoutPaneIds }
        return layoutPaneIds.filter { !minimizedPaneIds.contains($0) }
    }
}
