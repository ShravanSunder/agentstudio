import Foundation

@MainActor
struct WorkspacePaneFocusDerived {
    func currentFocus(
        workspaceTab: WorkspaceTabDerived,
        workspacePane: WorkspacePaneAtom,
        workspaceNavigationScope: WorkspaceNavigationScopeAtom
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
            if !drawer.paneIds.isEmpty {
                satisfiedRequirements.insert(.hasDrawerPanes)
            }
        }

        let drawerFocusState: WorkspacePaneFocus.DrawerFocusState
        switch normalizedDrawerFocusState(
            from: workspaceNavigationScope.scope,
            activePaneId: activePaneId,
            workspacePane: workspacePane
        ) {
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

    private func normalizedDrawerFocusState(
        from scope: WorkspaceNavigationScope,
        activePaneId: UUID,
        workspacePane: WorkspacePaneAtom
    ) -> WorkspaceNavigationScope {
        switch scope {
        case .mainPane:
            return .mainPane(paneId: activePaneId)
        case .emptyDrawer(let parentPaneId):
            guard activePaneId == parentPaneId,
                let drawer = workspacePane.pane(parentPaneId)?.drawer,
                drawer.isExpanded,
                drawer.paneIds.isEmpty
            else {
                return .mainPane(paneId: activePaneId)
            }
            return scope
        case .drawerPane(let parentPaneId, let paneId):
            guard activePaneId == parentPaneId,
                let drawer = workspacePane.pane(parentPaneId)?.drawer,
                drawer.isExpanded,
                drawer.activePaneId == paneId,
                drawer.paneIds.contains(paneId),
                !drawer.minimizedPaneIds.contains(paneId)
            else {
                return .mainPane(paneId: activePaneId)
            }
            return scope
        }
    }
}
