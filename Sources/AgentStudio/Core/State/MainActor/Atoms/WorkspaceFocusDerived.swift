import Foundation

@MainActor
struct WorkspaceFocusDerived {
    func currentFocus(
        workspaceTabLayout: WorkspaceTabLayoutAtom,
        workspacePane: WorkspacePaneAtom
    ) -> WorkspaceFocus {
        var satisfiedRequirements: Set<FocusRequirement> = []

        guard
            let activeTabId = workspaceTabLayout.activeTabId,
            let tab = workspaceTabLayout.tab(activeTabId)
        else {
            return .empty
        }

        satisfiedRequirements.insert(.hasActiveTab)

        if workspaceTabLayout.tabs.count > 1 {
            satisfiedRequirements.insert(.hasMultipleTabs)
        }

        if tab.activePaneIds.count > 1 {
            satisfiedRequirements.insert(.hasMultiplePanes)
        }

        if tab.arrangements.count > 1 {
            satisfiedRequirements.insert(.hasArrangements)
        }

        guard let activePaneId = tab.activePaneId else {
            return WorkspaceFocus(
                activeTabId: activeTabId,
                paneContentType: .noActivePane,
                satisfiedRequirements: satisfiedRequirements
            )
        }

        guard let pane = workspacePane.pane(activePaneId) else {
            return WorkspaceFocus(
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

        let paneContentType: WorkspaceFocus.ContentType
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

        return WorkspaceFocus(
            activeTabId: activeTabId,
            activePaneId: activePaneId,
            activeRepoId: pane.repoId,
            activeWorktreeId: pane.worktreeId,
            paneContentType: paneContentType,
            satisfiedRequirements: satisfiedRequirements
        )
    }
}
