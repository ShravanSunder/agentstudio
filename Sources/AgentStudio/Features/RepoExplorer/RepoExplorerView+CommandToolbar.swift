import AgentStudioCore
import AgentStudioSharedComponents

extension RepoExplorerView {
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

    func groupingModeIcon(for mode: RepoExplorerGroupingMode) -> AppEntityIcon {
        switch mode {
        case .repo: AppEntityIcon.repo
        case .pane: AppEntityIcon.pane
        case .tab: AppEntityIcon.tab
        }
    }
}
