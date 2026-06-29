extension AppCommand {
    func worktreeDefinition(label: String, icon: CommandIcon, helpText: String) -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            label: label,
            icon: icon,
            helpText: helpText,
            appliesTo: [.worktree],
            commandBarGroupName: "Repo",
            commandBarGroupPriority: CommandBarGroupPriority.repo
        )
    }

    func repoSidebarGroupingDefinition(_ groupingMode: RepoExplorerGroupingMode) -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            label: "Group Repos by \(groupingMode.title)",
            icon: groupingMode.icon,
            helpText: "Group the repo sidebar by \(groupingMode.title.lowercased())",
            commandBarGroupName: "Sidebar",
            commandBarGroupPriority: CommandBarGroupPriority.window
        )
    }

    func inboxGroupingDefinition(_ grouping: InboxNotificationGrouping) -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            label: "Group Inbox by \(grouping.commandLabel)",
            icon: grouping.icon,
            helpText: "Group inbox notifications by \(grouping.commandHelpTarget)",
            commandBarGroupName: "Inbox",
            commandBarGroupPriority: CommandBarGroupPriority.window
        )
    }

    func managementDefinition(shortcut: AppShortcut, label: String, icon: CommandIcon, helpText: String)
        -> AppCommandSpec
    {
        AppCommandSpec(
            command: self,
            shortcut: shortcut,
            label: label,
            icon: icon,
            helpText: helpText,
            requiresManagementLayer: true,
            isHiddenInCommandBar: true
        )
    }
}
