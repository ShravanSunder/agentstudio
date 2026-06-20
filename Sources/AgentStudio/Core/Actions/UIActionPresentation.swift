import Foundation

struct ActionSpec: Equatable, Sendable {
    let label: String
    let helpText: String
    let icon: CommandIcon
}

extension ActionSpec {
    func controlTooltipSource(
        provenance: CommandDisplayProvenance,
        textOverride: String? = nil,
        shortcutText: ShortcutDisplayText? = nil
    ) -> ControlTooltipSource {
        .display(
            CommandDisplayDescriptor(
                provenance: provenance,
                label: label,
                helpText: helpText,
                compactTooltipText: textOverride,
                shortcutDisplayText: shortcutText
            ))
    }

    func controlTooltipRenderValue(
        provenance: CommandDisplayProvenance,
        textOverride: String? = nil,
        shortcutText: ShortcutDisplayText? = nil
    ) -> ControlTooltipRenderValue {
        ControlTooltipResolver.resolve(
            controlTooltipSource(
                provenance: provenance,
                textOverride: textOverride,
                shortcutText: shortcutText
            ))
    }

    func controlToolTip(
        textOverride: String? = nil,
        shortcutText: ShortcutDisplayText? = nil
    ) -> String {
        controlTooltipRenderValue(
            provenance: .localAction(rawValue: label),
            textOverride: textOverride,
            shortcutText: shortcutText
        ).text
    }
}

extension KeyBinding {
    var displayText: ShortcutDisplayText {
        ShortcutDisplayText(value: displayString)
    }

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

enum LocalActionSpec {
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
    case toggleInboxRowStateFilter(showingUnreadOnly: Bool)
    case toggleInboxAttentionFilter(isAttentionOnly: Bool)
    case groupInboxNotifications
    case deleteInboxNotifications
    case cancel
    case add
    case rename
    case openPaneLocationInFinder
    case openPaneLocationInBookmarkedEditor
    case openPaneLocationInEditorMenu
    case toggleDrawer(isExpanded: Bool)
    case addDrawerPane

    var actionSpec: ActionSpec {
        switch self {
        case .quickOpen:
            return ActionSpec(
                label: "Quick Open", helpText: "Show the quick-open palette", icon: .system(.magnifyingglass))
        case .commandPalette:
            return ActionSpec(
                label: "Command Palette", helpText: "Show the command palette", icon: .system(.command))
        case .goToPane:
            return ActionSpec(label: "Go to Pane", helpText: "Show the pane picker", icon: .system(.terminal))
        case .openInMenu:
            return ActionSpec(
                label: "Open in...", helpText: "Choose an editor to open this worktree", icon: .system(.ellipsisCircle))
        case .setIconColorMenu:
            return ActionSpec(
                label: "Set Icon Color", helpText: "Choose a custom sidebar color", icon: .system(.paintpaletteFill))
        case .openInNewTab:
            return ActionSpec(
                label: "Open in New Tab", helpText: "Open this worktree in a new tab", icon: .system(.plusRectangle))
        case .openInPaneSplit:
            return ActionSpec(
                label: "Open in Pane (Split)", helpText: "Open this worktree in a split pane",
                icon: .system(.rectangleSplit2x1))
        case .goToTerminal:
            return ActionSpec(
                label: "Go to Terminal", helpText: "Focus the existing terminal for this worktree",
                icon: .system(.terminal))
        case .openInCursor:
            return ActionSpec(
                label: "Cursor", helpText: "Open this worktree in Cursor", icon: .octicon(.codeSquare))
        case .openInVSCode:
            return ActionSpec(
                label: "VS Code", helpText: "Open this worktree in VS Code", icon: .octicon(.vscode))
        case .revealInFinder:
            return ActionSpec(
                label: "Reveal in Finder", helpText: "Reveal this path in Finder", icon: .system(.folder))
        case .copyPath:
            return ActionSpec(
                label: "Copy Path", helpText: "Copy this path to the clipboard", icon: .system(.docOnClipboard))
        case .revealDataLocationInFinder:
            return ActionSpec(
                label: "Reveal in Finder", helpText: "Reveal the AgentStudio data folder in Finder",
                icon: .system(.folder))
        case .clearFilter:
            return ActionSpec(
                label: "Clear Filter", helpText: "Clear filter", icon: .system(.xmarkCircleFill))
        case .refreshWorktrees:
            return ActionSpec(
                label: "Refresh Worktrees", helpText: "Refresh watched worktrees", icon: .system(.arrowClockwise))
        case .chooseFolderToScan:
            return ActionSpec(
                label: "Choose a Folder to Scan…", helpText: "Choose a folder to scan",
                icon: .system(.folderFillBadgePlus))
        case .openAllInTabs:
            return ActionSpec(
                label: "Open All In Tabs", helpText: "Open all recent worktrees in tabs",
                icon: .system(.rectangleStack))
        case .extractPaneToNewTab:
            return ActionSpec(
                label: "Extract Pane to New Tab", helpText: "Move the active pane into a new tab",
                icon: .system(.arrowUpRightSquare))
        case .movePaneToTabMenu:
            return ActionSpec(
                label: "Move Pane to Tab", helpText: "Move the active pane into another tab",
                icon: .system(.filemenuAndPointerArrow))
        case .openGitHubInNewTab:
            return ActionSpec(
                label: "Open GitHub in New Tab", helpText: "Open GitHub in a new tab", icon: .system(.globe))
        case .arrangements:
            return ActionSpec(
                label: "Arrangements", helpText: "Manage tab arrangements", icon: .system(.rectangle3Group))
        case .saveCurrentLayoutAsArrangement:
            return ActionSpec(
                label: "Save Current Layout as Arrangement", helpText: "Save current layout as arrangement",
                icon: .system(.plus))
        case .showPane:
            return ActionSpec(label: "Show Pane", helpText: "Show pane", icon: .system(.eye))
        case .hidePane:
            return ActionSpec(label: "Hide Pane", helpText: "Hide pane", icon: .system(.eyeSlash))
        case .addDrawerTerminal:
            return ActionSpec(
                label: "Add Drawer Terminal", helpText: "Add a drawer terminal", icon: .system(.plus))
        case .resetIconColorDefault:
            return ActionSpec(
                label: "Reset to Default", helpText: "Reset the sidebar icon color", icon: .system(.paintpalette))
        case .browserBack:
            return ActionSpec(label: "Back", helpText: "Back (⌘[)", icon: .system(.chevronLeft))
        case .browserForward:
            return ActionSpec(label: "Forward", helpText: "Forward (⌘])", icon: .system(.chevronRight))
        case .browserStop:
            return ActionSpec(label: "Stop Loading", helpText: "Stop loading", icon: .system(.xmark))
        case .browserReload:
            return ActionSpec(label: "Reload", helpText: "Reload (⌘R)", icon: .system(.arrowClockwise))
        case .browserHome:
            return ActionSpec(label: "New Tab Page", helpText: "New tab page", icon: .system(.house))
        case .browserAddFavorite:
            return ActionSpec(
                label: "Add to Favorites", helpText: "Add to favorites (⌘D)", icon: .system(.star))
        case .browserRemoveFavorite:
            return ActionSpec(
                label: "Remove from Favorites", helpText: "Remove from favorites (⌘D)", icon: .system(.starFill))
        case .emptyTerminal:
            return ActionSpec(
                label: "Empty Terminal", helpText: "Open a new empty terminal tab", icon: .system(.terminal))
        case .openRepoWorktree:
            return ActionSpec(
                label: "Open Worktree...", helpText: "Open a discovered worktree in a tab", icon: .system(.folder))
        case .renameArrangement:
            return ActionSpec(label: "Rename...", helpText: "Rename this arrangement", icon: .system(.pencil))
        case .deleteArrangement:
            return ActionSpec(label: "Delete", helpText: "Delete this arrangement", icon: .system(.trash))
        case .addFavorite:
            return ActionSpec(
                label: "Add Favorite", helpText: "Add a saved favorite URL", icon: .system(.plus))
        case .clearAllHistory:
            return ActionSpec(
                label: "Clear All History", helpText: "Clear all saved browser history", icon: .system(.trash))
        case .toggleInboxRowStateFilter(let showingUnreadOnly):
            return ActionSpec(
                label: showingUnreadOnly ? "Show All Inbox Notifications" : "Show Unread Only",
                helpText: showingUnreadOnly
                    ? "Showing unread notifications; click to show all inbox notifications"
                    : "Showing all inbox notifications; click to show unread notifications only",
                icon: .system(.envelopeBadge)
            )
        case .toggleInboxAttentionFilter(let isAttentionOnly):
            return ActionSpec(
                label: isAttentionOnly ? "Show All Notifications" : "Show Attention Notifications",
                helpText: isAttentionOnly
                    ? "Showing attention notifications; click to show all notifications"
                    : "Showing all notifications; click to show attention notifications",
                icon: .system(.dotCircleViewfinder)
            )
        case .groupInboxNotifications:
            return ActionSpec(
                label: "Group Inbox Notifications",
                helpText: "Group inbox notifications",
                icon: .system(.squareStack3dUp)
            )
        case .deleteInboxNotifications:
            return ActionSpec(
                label: "Delete Inbox Notifications",
                helpText: "Open delete actions for inbox notifications",
                icon: .system(.deleteLeft)
            )
        case .cancel:
            return ActionSpec(label: "Cancel", helpText: "Cancel this action", icon: .system(.xmarkCircle))
        case .add:
            return ActionSpec(label: "Add", helpText: "Add this item", icon: .system(.plusCircle))
        case .rename:
            return ActionSpec(label: "Rename", helpText: "Rename this item", icon: .system(.pencil))
        case .openPaneLocationInFinder:
            return ActionSpec(
                label: "Open pane location in Finder", helpText: "Open pane location in Finder",
                icon: .system(.finder))
        case .openPaneLocationInBookmarkedEditor:
            return ActionSpec(
                label: "Open pane location in bookmarked editor",
                helpText: "Open pane location in the bookmarked editor",
                icon: .octicon(.codeSquare))
        case .openPaneLocationInEditorMenu:
            return ActionSpec(
                label: "Open pane location in app menu",
                helpText: "Choose an app for this pane location",
                icon: .system(.chevronUpChevronDown)
            )
        case .toggleDrawer(let isExpanded):
            return ActionSpec(
                label: isExpanded ? "Collapse Drawer" : "Expand Drawer",
                helpText: isExpanded ? "Collapse drawer" : "Expand drawer",
                icon: .system(.rectangleBottomhalfFilled)
            )
        case .addDrawerPane:
            return ActionSpec(label: "Add Drawer Pane", helpText: "Add drawer pane", icon: .system(.plus))
        }
    }
}
