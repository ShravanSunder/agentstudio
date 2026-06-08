import Foundation

@MainActor
struct WorkspacePaneFocusDerived {
    func currentFocus(
        workspaceTab: WorkspaceTabLayoutDerived,
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
        let drawerView = atom(\.arrangementView).drawerView(forParent: activePaneId)
        let normalizedFocusOwner = WorkspaceFocusOwnerNormalizer.normalize(
            requested: workspaceFocusOwner.owner,
            context: .init(
                activeMainPaneId: activePaneId,
                expandedDrawerParentPaneId: drawer?.isExpanded == true ? activePaneId : nil,
                paneIds: drawer?.paneIds ?? [],
                activeDrawerPaneId: drawerView?.activeChildId,
                minimizedDrawerPaneIds: drawerView?.minimizedPaneIds ?? []
            )
        )

        let drawerFocusState: WorkspacePaneFocus.DrawerFocusState
        // Identity (activePaneId / repoId / worktreeId / contentType)
        // must follow the FOCUSED pane — when focus is inside a drawer
        // child, command-bar filtering, status strip, and menu visibility
        // need to describe THAT pane, not the parent that hosts it.
        let focusedPane: Pane
        switch normalizedFocusOwner {
        case .mainPane:
            drawerFocusState = .inactive
            focusedPane = pane
        case .emptyDrawer(let parentPaneId):
            satisfiedRequirements.insert(.hasEmptyDrawerFocus)
            drawerFocusState = .emptyDrawer(parentPaneId: parentPaneId)
            // Empty drawer has no child to derive from; fall back to parent.
            focusedPane = pane
        case .drawerPane(let parentPaneId, let paneId):
            satisfiedRequirements.insert(.hasFocusedDrawerPane)
            drawerFocusState = .drawerPane(parentPaneId: parentPaneId, paneId: paneId)
            focusedPane = workspacePane.pane(paneId) ?? pane
        }

        let paneContentType: WorkspacePaneFocus.ContentType
        switch focusedPane.content {
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
            activePaneId: focusedPane.id,
            activeRepoId: focusedPane.repoId,
            activeWorktreeId: focusedPane.worktreeId,
            paneContentType: paneContentType,
            drawerFocusState: drawerFocusState,
            satisfiedRequirements: satisfiedRequirements
        )
    }
}
