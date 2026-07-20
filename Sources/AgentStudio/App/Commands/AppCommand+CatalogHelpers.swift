import AgentStudioProgrammaticControl
import Foundation

// MARK: - AppCommand Catalog Helpers

extension AppCommand {
    func hiddenTabSelectionDefinition(index: Int) -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            shortcut: Self.selectTabShortcut(index: index),
            label: "Select Tab \(index)",
            icon: .system(.rectangleStack),
            helpText: "Select tab \(index)",
            visibleWhen: [.hasActiveTab],
            commandBarGroupPriority: CommandBarGroupPriority.miscellaneous,
            isHiddenInCommandBar: true
        )
    }

    func hiddenFocusPaneDefinition(index: Int) -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            shortcut: Self.focusPaneShortcut(index: index),
            label: "Focus Pane \(index)",
            icon: .system(.rectangleSplit2x1),
            helpText: "Focus pane \(index)",
            visibleWhen: [.hasActiveTab],
            commandBarGroupName: "Focus",
            commandBarGroupPriority: CommandBarGroupPriority.focus,
            isHiddenInCommandBar: true
        )
    }

    func hiddenFocusDrawerPaneDefinition(index: Int) -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            label: "Focus Drawer Pane \(index)",
            icon: .system(.rectangleBottomhalfInsetFilled),
            helpText: "Focus drawer pane \(index)",
            visibleWhen: [.hasActivePane],
            commandBarGroupName: "Focus",
            commandBarGroupPriority: CommandBarGroupPriority.focus,
            isHiddenInCommandBar: true
        )
    }

    func focusDefinition(label: String, icon: CommandIcon, helpText: String) -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            label: label,
            icon: icon,
            helpText: helpText,
            visibleWhen: [.hasActiveTab, .hasMultiplePanes],
            commandBarGroupName: "Focus",
            commandBarGroupPriority: CommandBarGroupPriority.focus
        )
    }

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

    func inboxRowStateFilterDefinition() -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            label: "Set Inbox Row Filter",
            icon: .system(.envelopeBadge),
            helpText: "Set whether the inbox shows all or unread notifications",
            commandBarGroupName: "Inbox",
            commandBarGroupPriority: CommandBarGroupPriority.window,
            isHiddenInCommandBar: true,
            argumentSchema: [
                IPCCommandArgumentSchema(
                    name: "filter",
                    kind: .stringEnum(values: InboxNotificationRowStateFilter.allCases.map(\.rawValue)),
                    isRequired: true
                )
            ],
            ipcExposure: .headless(requiredPrivileges: [.sidebarStateMutate])
        )
    }

    func inboxContentModeDefinition() -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            label: "Set Inbox Content Mode",
            icon: .system(.dotCircleViewfinder),
            helpText: "Set which notification content lane the inbox shows",
            commandBarGroupName: "Inbox",
            commandBarGroupPriority: CommandBarGroupPriority.window,
            isHiddenInCommandBar: true,
            argumentSchema: [
                IPCCommandArgumentSchema(
                    name: "mode",
                    kind: .stringEnum(values: InboxNotificationContentMode.allCases.map(\.rawValue)),
                    isRequired: true
                )
            ],
            ipcExposure: .headless(requiredPrivileges: [.sidebarStateMutate])
        )
    }

    func repoFavoriteDefinition(
        label: String,
        icon: SystemSymbol,
        helpText: String
    ) -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            label: label,
            icon: .system(icon),
            helpText: helpText,
            appliesTo: [.repo],
            commandBarGroupName: "Repo",
            commandBarGroupPriority: CommandBarGroupPriority.repo,
            isHiddenInCommandBar: true,
            ipcExposure: .headless(
                targetKinds: [.repo],
                requiredPrivileges: [.sidebarStateMutate]
            )
        )
    }

    func arrangementDefinition(
        shortcut: AppShortcut? = nil,
        label: String,
        icon: CommandIcon,
        helpText: String
    ) -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            shortcut: shortcut,
            label: label,
            icon: icon,
            helpText: helpText,
            appliesTo: [.tab],
            visibleWhen: [.hasActiveTab, .hasArrangements],
            commandBarGroupName: "Tab",
            commandBarGroupPriority: CommandBarGroupPriority.tab
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
