import Foundation

// MARK: - AppCommand Catalog Helpers

extension AppCommand {
    /// Ordered array of tab selection commands (⌘1 through ⌘9)
    package static let selectTabCommands: [AppCommand] = [
        .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
        .selectTab6, .selectTab7, .selectTab8, .selectTab9,
    ]

    package static let focusPaneCommands: [AppCommand] = [
        .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
        .focusPane6, .focusPane7, .focusPane8, .focusPane9,
    ]

    package static let focusDrawerPaneCommands: [AppCommand] = [
        .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4, .focusDrawerPane5,
        .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8, .focusDrawerPane9,
    ]

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

    func bridgeWebViewReloadDefinition() -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            label: "Reload Bridge Web View",
            icon: .system(.arrowClockwise),
            helpText:
                "Reload the Bridge browser page and discard browser presentation state without refreshing worktree source data",
            visibleWhen: [.hasActivePane, .paneIsBridge],
            commandBarGroupName: "Bridge",
            commandBarGroupPriority: CommandBarGroupPriority.bridge
        )
    }

    func repoSidebarGroupingDefinition(
        label: String,
        icon: CommandIcon,
        helpTarget: String
    ) -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            label: "Group Repos by \(label)",
            icon: icon,
            helpText: "Group the repo sidebar by \(helpTarget)",
            commandBarGroupName: "Sidebar",
            commandBarGroupPriority: CommandBarGroupPriority.sidebar
        )
    }

    func repoSidebarVisibilityDefinition() -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            label: "Set Repo Sidebar Visibility Mode",
            icon: .system(.bookmark),
            helpText: "Set the repo sidebar visibility mode",
            commandBarGroupName: "Sidebar",
            commandBarGroupPriority: CommandBarGroupPriority.sidebar,
            isHiddenInCommandBar: true
        )
    }

    func repoSidebarSortOrderDefinition() -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            label: "Set Repo Sidebar Sort Order",
            icon: .system(.arrowUpArrowDown),
            helpText: "Set the repo sidebar sort order",
            commandBarGroupName: "Sidebar",
            commandBarGroupPriority: CommandBarGroupPriority.sidebar,
            isHiddenInCommandBar: true
        )
    }

    func inboxGroupingDefinition(
        label: String,
        icon: CommandIcon,
        helpTarget: String
    ) -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            label: "Group Inbox by \(label)",
            icon: icon,
            helpText: "Group inbox notifications by \(helpTarget)",
            commandBarGroupName: "Inbox",
            commandBarGroupPriority: CommandBarGroupPriority.inbox
        )
    }

    func inboxRowStateFilterDefinition() -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            label: "Set Inbox Row Filter",
            icon: .system(.envelopeBadge),
            helpText: "Set whether the inbox shows all or unread notifications",
            commandBarGroupName: "Inbox",
            commandBarGroupPriority: CommandBarGroupPriority.inbox,
            isHiddenInCommandBar: true
        )
    }

    func inboxContentModeDefinition() -> AppCommandSpec {
        AppCommandSpec(
            command: self,
            label: "Set Inbox Content Mode",
            icon: .system(.dotCircleViewfinder),
            helpText: "Set which notification content lane the inbox shows",
            commandBarGroupName: "Inbox",
            commandBarGroupPriority: CommandBarGroupPriority.inbox,
            isHiddenInCommandBar: true
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
            isHiddenInCommandBar: true
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
