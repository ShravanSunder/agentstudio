import Foundation

struct ActiveDrawerInboxTarget: Equatable {
    let parentPaneId: UUID
    let drawerPaneIds: [UUID]
}

enum ActiveDrawerInboxSelection: Equatable {
    case available(ActiveDrawerInboxTarget)
    case noActiveTab
    case noActivePane
    case noDrawer
    case drawerCollapsed
    case noActiveDrawerChild
    case noVisibleDrawerPanes
}

extension WorkspaceStore {
    func visiblePaneIdsForActiveExpandedDrawer() -> [UUID]? {
        guard case .available(let target) = activeDrawerInboxSelection() else {
            return nil
        }
        return target.drawerPaneIds
    }

    func activeDrawerInboxSelection() -> ActiveDrawerInboxSelection {
        guard let activeTabId = tabLayoutAtom.activeTabId else { return .noActiveTab }
        guard let activePaneId = tabLayoutAtom.tab(activeTabId)?.activePaneId else { return .noActivePane }
        guard let activePane = paneAtom.pane(activePaneId) else { return .noActivePane }
        let parentPaneId = activePane.parentPaneId ?? activePaneId
        guard let drawer = paneAtom.pane(parentPaneId)?.drawer else { return .noDrawer }
        guard drawer.isExpanded else { return .drawerCollapsed }
        guard drawer.activeChildId != nil else { return .noActiveDrawerChild }

        let visiblePaneIds = drawer.paneIds.filter { !drawer.minimizedPaneIds.contains($0) }
        guard !visiblePaneIds.isEmpty else { return .noVisibleDrawerPanes }
        return .available(ActiveDrawerInboxTarget(parentPaneId: parentPaneId, drawerPaneIds: visiblePaneIds))
    }
}
