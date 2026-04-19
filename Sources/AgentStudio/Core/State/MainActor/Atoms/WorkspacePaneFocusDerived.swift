import Foundation

@MainActor
struct WorkspacePaneFocusDerived {
    func currentFocus(
        workspaceTab: WorkspaceTabDerived,
        workspacePane: WorkspacePaneAtom,
        workspaceFocusOwner: WorkspaceFocusOwnerAtom
    ) -> WorkspacePaneFocus {
        var satisfiedRequirements: Set<FocusRequirement> = []

        guard
            let activeTabId = workspaceTab.shellAtom.activeTabId,
            let tab = workspaceTab.tab(activeTabId)
        else {
            return .empty
        }

        satisfiedRequirements.insert(.hasActiveTab)

        if workspaceTab.tabs.count > 1 {
            satisfiedRequirements.insert(.hasMultipleTabs)
        }

        if tab.activePaneIds.count > 1 {
            satisfiedRequirements.insert(.hasMultiplePanes)
        }

        if tab.arrangements.count > 1 {
            satisfiedRequirements.insert(.hasArrangements)
        }

        guard let activePaneId = tab.activePaneId else {
            return WorkspacePaneFocus(
                activeTabId: activeTabId,
                paneContentType: .noActivePane,
                satisfiedRequirements: satisfiedRequirements
            )
        }

        guard let pane = workspacePane.pane(activePaneId) else {
            return WorkspacePaneFocus(
                activeTabId: activeTabId,
                paneContentType: .noActivePane,
                satisfiedRequirements: satisfiedRequirements
            )
        }

        satisfiedRequirements.insert(.hasActivePane)

        if let drawer = pane.drawer {
            satisfiedRequirements.insert(.hasDrawer)
            if drawer.isExpanded, !drawer.paneIds.isEmpty {
                satisfiedRequirements.insert(.hasDrawerPanes)
            }
        }

        let drawer = pane.drawer
        let normalizedFocusOwner = WorkspaceFocusOwnerNormalizer.normalize(
            requested: workspaceFocusOwner.owner,
            context: .init(
                activeMainPaneId: activePaneId,
                expandedDrawerParentPaneId: drawer?.isExpanded == true ? activePaneId : nil,
                drawerPaneIds: drawer?.paneIds ?? [],
                activeDrawerPaneId: drawer?.activePaneId,
                minimizedDrawerPaneIds: drawer?.minimizedPaneIds ?? []
            )
        )

        let drawerFocusState: WorkspacePaneFocus.DrawerFocusState
        switch normalizedFocusOwner {
        case .mainPane:
            drawerFocusState = .inactive
        case .emptyDrawer(let parentPaneId):
            satisfiedRequirements.insert(.hasEmptyDrawerFocus)
            drawerFocusState = .emptyDrawer(parentPaneId: parentPaneId)
        case .drawerPane(let parentPaneId, let paneId):
            satisfiedRequirements.insert(.hasFocusedDrawerPane)
            drawerFocusState = .drawerPane(parentPaneId: parentPaneId, paneId: paneId)
        }

        let paneContentType: WorkspacePaneFocus.ContentType
        switch pane.content {
        case .terminal:
            paneContentType = .terminal
        case .webview:
            paneContentType = .webview
        case .bridgePanel:
            paneContentType = .bridge
        case .codeViewer:
            paneContentType = .codeViewer
        case .unsupported:
            paneContentType = .unsupported
        }

        return WorkspacePaneFocus(
            activeTabId: activeTabId,
            activePaneId: activePaneId,
            activeRepoId: pane.repoId,
            activeWorktreeId: pane.worktreeId,
            paneContentType: paneContentType,
            drawerFocusState: drawerFocusState,
            satisfiedRequirements: satisfiedRequirements
        )
    }
}
