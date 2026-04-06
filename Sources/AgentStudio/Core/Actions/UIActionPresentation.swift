import Foundation

enum ActionIconDescriptor: Equatable, Sendable {
    case system(String)
    case octicon(String)
}

struct ActionPresentation: Equatable, Sendable {
    let label: String
    let helpText: String
    let icon: ActionIconDescriptor?
}

extension KeyBinding {
    var displayString: String {
        var keys: [String] = []
        if modifiers.contains(.command) { keys.append("⌘") }
        if modifiers.contains(.shift) { keys.append("⇧") }
        if modifiers.contains(.option) { keys.append("⌥") }
        if modifiers.contains(.control) { keys.append("⌃") }
        keys.append(displayKey)
        return keys.joined()
    }

    private var displayKey: String {
        key.count == 1 ? key.uppercased() : key
    }
}

extension CommandDefinition {
    var presentation: ActionPresentation {
        ActionPresentation(
            label: label,
            helpText: helpText,
            icon: icon.map(ActionIconDescriptor.system)
        )
    }

    var controlToolTip: String {
        if let keyBinding {
            return "\(presentation.label) (\(keyBinding.displayString))"
        }
        return presentation.helpText
    }
}

enum LocalActionPresentation {
    case quickOpen
    case commandPalette
    case goToPane
    case openInMenu
    case setIconColorMenu
    case openInNewTab
    case openInPaneSplit
    case goToTerminal
    case openInCursor
    case openInVSCode
    case revealInFinder
    case copyPath
    case revealDataLocationInFinder
    case openZellijConfig
    case clearFilter
    case refreshWorktrees
    case chooseFolderToScan
    case openAllInTabs
    case extractPaneToNewTab
    case movePaneToTabMenu
    case openGitHubInNewTab
    case arrangements
    case saveCurrentLayoutAsArrangement
    case showPane
    case hidePane
    case addDrawerTerminal
    case resetIconColorDefault
    case browserBack
    case browserForward
    case browserStop
    case browserReload
    case browserHome
    case browserAddFavorite
    case browserRemoveFavorite
    case emptyTerminal
    case openRepoWorktree
    case renameArrangement
    case deleteArrangement
    case addFavorite
    case clearAllHistory
    case cancel
    case add
    case rename
    case openPaneLocationInFinder
    case openPaneLocationInPreferredEditor
    case toggleDrawer(isExpanded: Bool)
    case addDrawerPane

    var presentation: ActionPresentation {
        switch self {
        case .quickOpen:
            return ActionPresentation(
                label: "Quick Open", helpText: "Show the quick-open palette", icon: .system("magnifyingglass"))
        case .commandPalette:
            return ActionPresentation(
                label: "Command Palette", helpText: "Show the command palette", icon: .system("command"))
        case .goToPane:
            return ActionPresentation(label: "Go to Pane", helpText: "Show the pane picker", icon: .system("terminal"))
        case .openInMenu:
            return ActionPresentation(
                label: "Open in...", helpText: "Choose an editor to open this worktree", icon: nil)
        case .setIconColorMenu:
            return ActionPresentation(label: "Set Icon Color", helpText: "Choose a custom sidebar color", icon: nil)
        case .openInNewTab:
            return ActionPresentation(
                label: "Open in New Tab", helpText: "Open this worktree in a new tab", icon: .system("plus.rectangle"))
        case .openInPaneSplit:
            return ActionPresentation(
                label: "Open in Pane (Split)", helpText: "Open this worktree in a split pane",
                icon: .system("rectangle.split.2x1"))
        case .goToTerminal:
            return ActionPresentation(
                label: "Go to Terminal", helpText: "Focus the existing terminal for this worktree",
                icon: .system("terminal"))
        case .openInCursor:
            return ActionPresentation(
                label: "Cursor", helpText: "Open this worktree in Cursor", icon: .octicon("octicon-code-square"))
        case .openInVSCode:
            return ActionPresentation(
                label: "VS Code", helpText: "Open this worktree in VS Code", icon: .octicon("octicon-vscode"))
        case .revealInFinder:
            return ActionPresentation(
                label: "Reveal in Finder", helpText: "Reveal this path in Finder", icon: .system("folder"))
        case .copyPath:
            return ActionPresentation(
                label: "Copy Path", helpText: "Copy this path to the clipboard", icon: .system("doc.on.clipboard"))
        case .revealDataLocationInFinder:
            return ActionPresentation(
                label: "Reveal in Finder", helpText: "Reveal the AgentStudio data folder in Finder",
                icon: .system("folder"))
        case .openZellijConfig:
            return ActionPresentation(
                label: "Open Zellij Config", helpText: "Open the Zellij configuration folder", icon: .system("folder"))
        case .clearFilter:
            return ActionPresentation(
                label: "Clear Filter", helpText: "Clear filter", icon: .system("xmark.circle.fill"))
        case .refreshWorktrees:
            return ActionPresentation(
                label: "Refresh Worktrees", helpText: "Refresh watched worktrees", icon: .system("arrow.clockwise"))
        case .chooseFolderToScan:
            return ActionPresentation(
                label: "Choose a Folder to Scan…", helpText: "Choose a folder to scan",
                icon: .system("folder.badge.plus"))
        case .openAllInTabs:
            return ActionPresentation(
                label: "Open All In Tabs", helpText: "Open all recent worktrees in tabs",
                icon: .system("rectangle.stack"))
        case .extractPaneToNewTab:
            return ActionPresentation(
                label: "Extract Pane to New Tab", helpText: "Move the active pane into a new tab",
                icon: .system("arrow.up.right.square"))
        case .movePaneToTabMenu:
            return ActionPresentation(
                label: "Move Pane to Tab", helpText: "Move the active pane into another tab", icon: nil)
        case .openGitHubInNewTab:
            return ActionPresentation(
                label: "Open GitHub in New Tab", helpText: "Open GitHub in a new tab", icon: .system("globe"))
        case .arrangements:
            return ActionPresentation(
                label: "Arrangements", helpText: "Manage tab arrangements", icon: .system("rectangle.3.group"))
        case .saveCurrentLayoutAsArrangement:
            return ActionPresentation(
                label: "Save Current Layout as Arrangement", helpText: "Save current layout as arrangement",
                icon: .system("plus"))
        case .showPane:
            return ActionPresentation(label: "Show Pane", helpText: "Show pane", icon: .system("eye"))
        case .hidePane:
            return ActionPresentation(label: "Hide Pane", helpText: "Hide pane", icon: .system("eye.slash"))
        case .addDrawerTerminal:
            return ActionPresentation(
                label: "Add Drawer Terminal", helpText: "Add a drawer terminal", icon: .system("plus"))
        case .resetIconColorDefault:
            return ActionPresentation(label: "Reset to Default", helpText: "Reset the sidebar icon color", icon: nil)
        case .browserBack:
            return ActionPresentation(label: "Back", helpText: "Back (⌘[)", icon: .system("chevron.left"))
        case .browserForward:
            return ActionPresentation(label: "Forward", helpText: "Forward (⌘])", icon: .system("chevron.right"))
        case .browserStop:
            return ActionPresentation(label: "Stop Loading", helpText: "Stop loading", icon: .system("xmark"))
        case .browserReload:
            return ActionPresentation(label: "Reload", helpText: "Reload (⌘R)", icon: .system("arrow.clockwise"))
        case .browserHome:
            return ActionPresentation(label: "New Tab Page", helpText: "New tab page", icon: .system("house"))
        case .browserAddFavorite:
            return ActionPresentation(
                label: "Add to Favorites", helpText: "Add to favorites (⌘D)", icon: .system("star"))
        case .browserRemoveFavorite:
            return ActionPresentation(
                label: "Remove from Favorites", helpText: "Remove from favorites (⌘D)", icon: .system("star.fill"))
        case .emptyTerminal:
            return ActionPresentation(
                label: "Empty Terminal", helpText: "Open a new empty terminal tab", icon: .system("terminal"))
        case .openRepoWorktree:
            return ActionPresentation(
                label: "Open Repo/Worktree...", helpText: "Open a repo or worktree in a tab", icon: .system("folder"))
        case .renameArrangement:
            return ActionPresentation(label: "Rename...", helpText: "Rename this arrangement", icon: .system("pencil"))
        case .deleteArrangement:
            return ActionPresentation(label: "Delete", helpText: "Delete this arrangement", icon: .system("trash"))
        case .addFavorite:
            return ActionPresentation(
                label: "Add Favorite", helpText: "Add a saved favorite URL", icon: .system("plus"))
        case .clearAllHistory:
            return ActionPresentation(
                label: "Clear All History", helpText: "Clear all saved browser history", icon: .system("trash"))
        case .cancel:
            return ActionPresentation(label: "Cancel", helpText: "Cancel this action", icon: nil)
        case .add:
            return ActionPresentation(label: "Add", helpText: "Add this item", icon: nil)
        case .rename:
            return ActionPresentation(label: "Rename", helpText: "Rename this item", icon: nil)
        case .openPaneLocationInFinder:
            return ActionPresentation(
                label: "Open pane location in Finder", helpText: "Open pane location in Finder",
                icon: .system("macwindow"))
        case .openPaneLocationInPreferredEditor:
            return ActionPresentation(
                label: "Open pane location in Cursor or VS Code", helpText: "Open pane location in Cursor or VS Code",
                icon: .octicon("octicon-code-square"))
        case .toggleDrawer(let isExpanded):
            return ActionPresentation(
                label: isExpanded ? "Collapse Drawer" : "Expand Drawer",
                helpText: isExpanded ? "Collapse drawer" : "Expand drawer",
                icon: .system("rectangle.bottomhalf.filled")
            )
        case .addDrawerPane:
            return ActionPresentation(label: "Add Drawer Pane", helpText: "Add drawer pane", icon: .system("plus"))
        }
    }
}
