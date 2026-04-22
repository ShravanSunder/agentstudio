import Foundation

@MainActor
struct CommandContextDerived {
    func currentFocus(
        workspaceTab: WorkspaceTabDerived,
        workspacePane: WorkspacePaneAtom
    ) -> CommandContext {
        var satisfiedRequirements: Set<CommandRequirement> = []

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
            return CommandContext(
                activeTabId: activeTabId,
                paneContentType: .noActivePane,
                satisfiedRequirements: satisfiedRequirements
            )
        }

        guard let pane = workspacePane.pane(activePaneId) else {
            return CommandContext(
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

        let paneContentType: CommandContext.ContentType
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

        return CommandContext(
            activeTabId: activeTabId,
            activePaneId: activePaneId,
            activeRepoId: pane.repoId,
            activeWorktreeId: pane.worktreeId,
            paneContentType: paneContentType,
            satisfiedRequirements: satisfiedRequirements
        )
    }
}
