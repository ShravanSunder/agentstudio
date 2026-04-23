import Foundation

enum ActiveDrawerInboxSelection: Equatable {
    case available([UUID])
    case noActiveTab
    case noActivePane
    case noDrawer
    case drawerCollapsed
    case noActiveDrawerChild
    case noVisibleDrawerPanes
}

extension WorkspaceStore {
    func visiblePaneIdsForActiveExpandedDrawer() -> [UUID]? {
        guard case .available(let paneIds) = activeDrawerInboxSelection() else {
            return nil
        }
        return paneIds
    }

    func activeDrawerInboxSelection() -> ActiveDrawerInboxSelection {
        guard let activeTabId = tabLayoutAtom.activeTabId else { return .noActiveTab }
        guard let activePaneId = tabLayoutAtom.tab(activeTabId)?.activePaneId else { return .noActivePane }
        guard let drawer = paneAtom.pane(activePaneId)?.drawer else { return .noDrawer }
        guard drawer.isExpanded else { return .drawerCollapsed }
        guard drawer.activeChildId != nil else { return .noActiveDrawerChild }

        let visiblePaneIds = drawer.paneIds.filter { !drawer.minimizedPaneIds.contains($0) }
        guard !visiblePaneIds.isEmpty else { return .noVisibleDrawerPanes }
        return .available(visiblePaneIds)
    }
}
