import Foundation
import os.log

private let workspaceArrangementViewLogger = Logger(
    subsystem: "com.agentstudio",
    category: "WorkspaceArrangementViewDerived"
)

@MainActor
struct WorkspaceArrangementViewDerived {
    let tabLayoutAtom: WorkspaceTabLayoutAtom
    let paneAtom: WorkspacePaneAtom
    let managementLayerAtom: ManagementLayerAtom

    func activeVisiblePaneIds(forTab tabId: UUID) -> [UUID] {
        guard let arrangement = tabLayoutAtom.tab(tabId)?.activeArrangement else {
            workspaceArrangementViewLogger.warning("activeVisiblePaneIds: tab \(tabId) not found")
            return []
        }
        return visiblePaneIds(
            layoutPaneIds: arrangement.layout.paneIds,
            minimizedPaneIds: arrangement.minimizedPaneIds
        )
    }

    func drawerView(forParent parentPaneId: UUID) -> DrawerView? {
        guard
            let tab = tabLayoutAtom.tabContaining(paneId: parentPaneId),
            let drawer = paneAtom.pane(parentPaneId)?.drawer
        else { return nil }
        if let drawerView = tab.activeArrangement.drawerViews[drawer.drawerId] {
            return drawerView
        }
        return drawer.paneIds.isEmpty ? DrawerView() : nil
    }

    func drawerVisiblePaneIds(forParent parentPaneId: UUID) -> [UUID] {
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
