import Foundation

extension AppCommand {
    func hiddenTabSelectionDefinition(index: Int) -> CommandSpec {
        CommandSpec(
            command: self,
            shortcut: selectTabShortcut(index: index),
            label: "Select Tab \(index)",
            icon: .system(.rectangleStack),
            helpText: "Select tab \(index)",
            visibleWhen: [.hasActiveTab],
            commandBarGroupPriority: CommandBarGroupPriority.miscellaneous,
            isHiddenInCommandBar: true
        )
    }

    func focusDefinition(label: String, icon: SystemSymbol, helpText: String) -> CommandSpec {
        CommandSpec(
            command: self,
            label: label,
            icon: .system(icon),
            helpText: helpText,
            visibleWhen: [.hasActiveTab, .hasMultiplePanes],
            commandBarGroupName: "Focus",
            commandBarGroupPriority: CommandBarGroupPriority.focus
        )
    }

    func arrangementDefinition(label: String, icon: SystemSymbol, helpText: String) -> CommandSpec {
        CommandSpec(
            command: self,
            label: label,
            icon: .system(icon),
            helpText: helpText,
            appliesTo: [.tab],
            visibleWhen: [.hasActiveTab, .hasArrangements],
            commandBarGroupName: "Tab",
            commandBarGroupPriority: CommandBarGroupPriority.tab
        )
    }

    func worktreeDefinition(label: String, icon: SystemSymbol, helpText: String) -> CommandSpec {
        CommandSpec(
            command: self,
            label: label,
            icon: .system(icon),
            helpText: helpText,
            appliesTo: [.worktree],
            commandBarGroupName: "Repo",
            commandBarGroupPriority: CommandBarGroupPriority.repo
        )
    }

    func managementDefinition(shortcut: AppShortcut, label: String, icon: SystemSymbol, helpText: String) -> CommandSpec
    {
        CommandSpec(
            command: self,
            shortcut: shortcut,
            label: label,
            icon: .system(icon),
            helpText: helpText,
            requiresManagementLayer: true,
            isHiddenInCommandBar: true
        )
    }

    func selectTabShortcut(index: Int) -> AppShortcut {
        switch index {
        case 1: return .selectTab1
        case 2: return .selectTab2
        case 3: return .selectTab3
        case 4: return .selectTab4
        case 5: return .selectTab5
        case 6: return .selectTab6
        case 7: return .selectTab7
        case 8: return .selectTab8
        case 9: return .selectTab9
        default:
            preconditionFailure("Unsupported tab shortcut index \(index)")
        }
    }
}
