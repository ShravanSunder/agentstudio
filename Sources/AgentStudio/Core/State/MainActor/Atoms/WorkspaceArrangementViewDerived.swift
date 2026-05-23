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
            minimizedPaneIds: arrangement.minimizedPaneIds.rawUUIDs,
            showsMinimizedPanes: effectiveShowsMinimizedPanes(for: arrangement)
        )
    }

    func effectiveShowsMinimizedPanes(forTab tabId: UUID) -> Bool {
        guard let arrangement = tabLayoutAtom.tab(tabId)?.activeArrangement else { return true }
        return effectiveShowsMinimizedPanes(for: arrangement)
    }

    func drawerView(forParent parentPaneId: UUID) -> DrawerView? {
        drawerViewState(forParent: parentPaneId)?.drawerView
    }

    func drawerViewState(forParent parentPaneId: UUID) -> DrawerViewState? {
        guard
            let tab = tabLayoutAtom.tabContaining(paneId: parentPaneId),
            let drawer = paneAtom.pane(parentPaneId)?.drawer
        else { return nil }
        if let drawerView = tab.activeArrangement.drawerViews[drawer.drawerId] {
            return .populated(drawerView)
        }
        return drawer.paneIds.isEmpty ? .empty : .missingForNonEmptyDrawer(drawerId: DrawerId(drawer.drawerId))
    }

    func drawerVisiblePaneIds(forParent parentPaneId: UUID) -> [UUID] {
        guard
            let tab = tabLayoutAtom.tabContaining(paneId: parentPaneId),
            let drawerView = drawerView(forParent: parentPaneId)
        else { return [] }
        return visiblePaneIds(
            layoutPaneIds: drawerView.layout.paneIds,
            minimizedPaneIds: drawerView.minimizedPaneIds.rawUUIDs,
            showsMinimizedPanes: effectiveShowsMinimizedPanes(for: tab.activeArrangement)
        )
    }

    func activePaneId(forTab tabId: UUID) -> UUID? {
        tabLayoutAtom.tab(tabId)?.activeArrangement.activePaneId?.rawValue
    }

    func activeMinimizedPaneIds(forTab tabId: UUID) -> Set<UUID> {
        tabLayoutAtom.tab(tabId)?.activeArrangement.minimizedPaneIds.rawUUIDs ?? []
    }

    private func effectiveShowsMinimizedPanes(for arrangement: PaneArrangement) -> Bool {
        managementLayerAtom.isActive ? true : arrangement.showsMinimizedPanes
    }

    private func visiblePaneIds(
        layoutPaneIds: [UUID],
        minimizedPaneIds: Set<UUID>,
        showsMinimizedPanes: Bool
    ) -> [UUID] {
        guard !showsMinimizedPanes else { return layoutPaneIds }
        return layoutPaneIds.filter { !minimizedPaneIds.contains($0) }
    }
}
