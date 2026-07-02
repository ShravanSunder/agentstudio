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
