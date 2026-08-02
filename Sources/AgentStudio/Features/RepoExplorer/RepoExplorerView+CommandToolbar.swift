import AgentStudioCore

extension RepoExplorerView {
    static func argumentCommandCapabilities(
        nextVisibilityMode: RepoExplorerVisibilityMode,
        nextSortOrder: RepoExplorerSortOrder,
        canSetVisibilityMode: ((RepoExplorerVisibilityMode) -> Bool)?,
        canSetSortOrder: ((RepoExplorerSortOrder) -> Bool)?
    ) -> [AppCommand: Bool] {
        var capabilities: [AppCommand: Bool] = [:]
        if let canSetVisibilityMode {
            capabilities[.setRepoSidebarVisibilityMode] = canSetVisibilityMode(nextVisibilityMode)
        }
        if let canSetSortOrder {
            capabilities[.setRepoSidebarSortOrder] = canSetSortOrder(nextSortOrder)
        }
        return capabilities
    }

    func presentedGroupingCommand(
        for mode: RepoExplorerGroupingMode,
        in commandPresentation: RepoExplorerToolbarCommandPresentation
    ) -> RepoExplorerPresentedCommand {
        guard let presentedCommand = commandPresentation.command(groupingCommand(for: mode)) else {
            preconditionFailure("Grouping popover received a presentation-denied mode")
        }
        return presentedCommand
    }

    func groupingCommand(for mode: RepoExplorerGroupingMode) -> AppCommand {
        switch mode {
        case .repo: .setRepoSidebarGroupingRepo
        case .pane: .setRepoSidebarGroupingPane
        case .tab: .setRepoSidebarGroupingTab
        }
    }
}
