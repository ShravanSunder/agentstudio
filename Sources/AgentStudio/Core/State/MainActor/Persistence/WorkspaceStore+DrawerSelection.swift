import Foundation

extension WorkspaceStore {
    func visiblePaneIdsForActiveExpandedDrawer() -> [UUID]? {
        guard
            let activeTabId = tabLayoutAtom.activeTabId,
            let activePaneId = tabLayoutAtom.tab(activeTabId)?.activePaneId,
            let drawer = paneAtom.pane(activePaneId)?.drawer,
            drawer.isExpanded,
            drawer.activeChildId != nil
        else {
            return nil
        }

        let visiblePaneIds = drawer.paneIds.filter { !drawer.minimizedPaneIds.contains($0) }
        return visiblePaneIds.isEmpty ? nil : visiblePaneIds
    }
}
