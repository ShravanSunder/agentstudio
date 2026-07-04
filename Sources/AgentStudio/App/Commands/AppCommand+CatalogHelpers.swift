import AgentStudioProgrammaticControl

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
            commandBarGroupPriority: CommandBarGroupPriority.window,
            ipcExposure: .headless(requiredPrivileges: [.sidebarStateMutate])
        )
    }

    func repoSidebarVisibilityDefinition() -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            label: "Set Repo Sidebar Visibility Mode",
            icon: .system(.bookmark),
            helpText: "Set the repo sidebar visibility mode",
            commandBarGroupName: "Sidebar",
            commandBarGroupPriority: CommandBarGroupPriority.window,
            isHiddenInCommandBar: true,
            argumentSchema: [
                IPCCommandArgumentSchema(
                    name: "mode",
                    kind: .stringEnum(values: RepoExplorerVisibilityMode.allCases.map(\.rawValue)),
                    isRequired: true
                )
            ],
            ipcExposure: .headless(requiredPrivileges: [.sidebarStateMutate])
        )
    }

    func repoSidebarSortOrderDefinition() -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            label: "Set Repo Sidebar Sort Order",
            icon: .system(.arrowUpArrowDown),
            helpText: "Set the repo sidebar sort order",
            commandBarGroupName: "Sidebar",
            commandBarGroupPriority: CommandBarGroupPriority.window,
            isHiddenInCommandBar: true,
            argumentSchema: [
                IPCCommandArgumentSchema(
                    name: "order",
                    kind: .stringEnum(values: RepoExplorerSortOrder.allCases.map(\.rawValue)),
                    isRequired: true
                )
            ],
            ipcExposure: .headless(requiredPrivileges: [.sidebarStateMutate])
        )
    }

    func inboxGroupingDefinition(_ grouping: InboxNotificationGrouping) -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            label: "Group Inbox by \(grouping.commandLabel)",
            icon: grouping.icon,
            helpText: "Group inbox notifications by \(grouping.commandHelpTarget)",
            commandBarGroupName: "Inbox",
            commandBarGroupPriority: CommandBarGroupPriority.window,
            ipcExposure: .headless(requiredPrivileges: [.sidebarStateMutate])
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
