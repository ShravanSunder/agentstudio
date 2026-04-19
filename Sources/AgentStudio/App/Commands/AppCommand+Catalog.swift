import Foundation

// MARK: - AppCommand Helpers

extension AppCommand {
    private enum CommandBarGroupPriority {
        static let pane = 0
        static let focus = 1
        static let tab = 2
        static let repo = 3
        static let window = 4
        static let webview = 5
        static let auth = 6
        static let miscellaneous = 7
    }

    /// Ordered array of tab selection commands (⌘1 through ⌘9)
    static let selectTabCommands: [AppCommand] = [
        .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
        .selectTab6, .selectTab7, .selectTab8, .selectTab9,
    ]

    var definition: CommandSpec {
        switch self {
        case .closeTab:
            return CommandSpec(
                command: self,
                shortcut: .closeTab,
                label: "Close Tab",
                icon: "xmark",
                helpText: "Close the active tab",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .breakUpTab:
            return CommandSpec(
                command: self,
                label: "Split Tab Into Individuals",
                icon: "rectangle.split.3x1",
                helpText: "Split each visible pane in the active tab into its own tab",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab, .hasMultiplePanes],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .renameTab:
            return CommandSpec(
                command: self,
                label: "Rename Tab...",
                icon: "pencil",
                helpText: "Rename the current tab",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .newTerminalInTab:
            return CommandSpec(
                command: self,
                label: "Add Terminal to Tab",
                icon: "terminal",
                helpText: "Add a new terminal to the active tab",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .newTab:
            return CommandSpec(
                command: self,
                label: "New Tab",
                icon: "plus.square",
                helpText: "Create a new terminal tab",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .undoCloseTab:
            return CommandSpec(
                command: self,
                shortcut: .undoCloseTab,
                label: "Undo Close Tab",
                icon: "arrow.uturn.backward",
                helpText: "Restore the most recently closed tab",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .selectTab:
            return CommandSpec(
                command: self,
                label: "Select Tab",
                icon: "rectangle.stack",
                helpText: "Select a specific tab",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab,
                isHiddenInCommandBar: true
            )
        case .nextTab:
            return CommandSpec(
                command: self,
                shortcut: .nextTab,
                label: "Next Tab",
                icon: "chevron.right",
                helpText: "Move to the next tab",
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .prevTab:
            return CommandSpec(
                command: self,
                shortcut: .prevTab,
                label: "Previous Tab",
                icon: "chevron.left",
                helpText: "Move to the previous tab",
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .selectTab1:
            return hiddenTabSelectionDefinition(index: 1)
        case .selectTab2:
            return hiddenTabSelectionDefinition(index: 2)
        case .selectTab3:
            return hiddenTabSelectionDefinition(index: 3)
        case .selectTab4:
            return hiddenTabSelectionDefinition(index: 4)
        case .selectTab5:
            return hiddenTabSelectionDefinition(index: 5)
        case .selectTab6:
            return hiddenTabSelectionDefinition(index: 6)
        case .selectTab7:
            return hiddenTabSelectionDefinition(index: 7)
        case .selectTab8:
            return hiddenTabSelectionDefinition(index: 8)
        case .selectTab9:
            return hiddenTabSelectionDefinition(index: 9)
        case .closePane:
            return CommandSpec(
                command: self,
                label: "Close Pane",
                icon: "xmark.square",
                helpText: "Close the active pane",
                appliesTo: [.pane, .floatingTerminal],
                requiresManagementLayer: true,
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .extractPaneToTab:
            return CommandSpec(
                command: self,
                label: "Move Pane to New Tab",
                icon: "arrow.up.right.square",
                helpText: "Move the active pane into a new tab",
                appliesTo: [.pane, .floatingTerminal],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .movePaneToTab:
            return CommandSpec(
                command: self,
                label: "Move Pane to Existing Tab",
                icon: "arrow.left.and.right.square",
                helpText: "Move the active pane into another existing tab",
                appliesTo: [.pane],
                requiresManagementLayer: true,
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .focusPane:
            return CommandSpec(
                command: self,
                label: "Focus Pane",
                icon: "scope",
                helpText: "Focus a specific pane",
                appliesTo: [.pane, .floatingTerminal],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane,
                isHiddenInCommandBar: true
            )
        case .scrollToBottom:
            return CommandSpec(
                command: self,
                shortcut: .scrollToBottom,
                label: "Scroll to Bottom",
                icon: "arrow.down.to.line",
                helpText: "Scroll the active terminal pane to the bottom of its scrollback",
                appliesTo: [.pane, .floatingTerminal],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .splitRight:
            return CommandSpec(
                command: self,
                label: "Split Right",
                icon: "rectangle.split.1x2",
                helpText: "Split the active pane to the right",
                appliesTo: [.pane, .tab],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .splitLeft:
            return CommandSpec(
                command: self,
                label: "Split Left",
                icon: "rectangle.split.1x2",
                helpText: "Split the active pane to the left",
                appliesTo: [.pane, .tab],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .equalizePanes:
            return CommandSpec(
                command: self,
                label: "Equalize Panes",
                icon: "equal.square",
                helpText: "Reset all pane sizes in the active tab to equal widths",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab, .hasMultiplePanes],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .focusPaneLeft:
            return focusDefinition(
                label: "Focus Pane Left",
                icon: "arrow.left",
                helpText: "Move focus to the pane on the left"
            )
        case .focusPaneRight:
            return focusDefinition(
                label: "Focus Pane Right",
                icon: "arrow.right",
                helpText: "Move focus to the pane on the right"
            )
        case .focusPaneUp:
            return focusDefinition(
                label: "Focus Pane Up",
                icon: "arrow.up",
                helpText: "Move focus to the pane above"
            )
        case .focusPaneDown:
            return focusDefinition(
                label: "Focus Pane Down",
                icon: "arrow.down",
                helpText: "Move focus to the pane below"
            )
        case .focusNextPane:
            return focusDefinition(
                label: "Focus Next Pane",
                icon: "arrow.right.circle",
                helpText: "Move focus to the next pane"
            )
        case .focusPrevPane:
            return focusDefinition(
                label: "Focus Previous Pane",
                icon: "arrow.left.circle",
                helpText: "Move focus to the previous pane"
            )
        case .toggleSplitZoom:
            return CommandSpec(
                command: self,
                label: "Toggle Split Zoom",
                icon: "arrow.up.left.and.arrow.down.right.magnifyingglass",
                helpText: "Toggle zoom for the active pane",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane, .hasMultiplePanes],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .minimizePane:
            return CommandSpec(
                command: self,
                label: "Minimize Pane",
                icon: "minus.circle",
                helpText: "Minimize the active pane",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .expandPane:
            return CommandSpec(
                command: self,
                label: "Expand Pane",
                icon: "arrow.up.left.and.arrow.down.right",
                helpText: "Expand a minimized pane back into the layout",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .switchArrangement:
            return arrangementDefinition(
                label: "Switch Arrangement",
                icon: "rectangle.3.group",
                helpText: "Switch the active tab to a saved arrangement"
            )
        case .saveArrangement:
            return CommandSpec(
                command: self,
                label: "Save Arrangement As...",
                icon: "rectangle.3.group.fill",
                helpText: "Save the current tab layout as a named arrangement",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .deleteArrangement:
            return arrangementDefinition(
                label: "Delete Arrangement",
                icon: "rectangle.3.group.bubble",
                helpText: "Delete a saved arrangement from the active tab"
            )
        case .renameArrangement:
            return arrangementDefinition(
                label: "Rename Arrangement",
                icon: "pencil",
                helpText: "Rename a saved arrangement in the active tab"
            )
        case .enterDrawer:
            return CommandSpec(
                command: self,
                label: "Enter Drawer",
                icon: "rectangle.bottomhalf.filled",
                helpText: "Open the active drawer and focus its selected pane",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown, .focusDrawerPaneRight:
            let displayShortcutTrigger: ShortcutTrigger =
                switch self {
                case .focusDrawerPaneUp:
                    .init(key: .character(.i), modifiers: [.option])
                case .focusDrawerPaneLeft:
                    .init(key: .character(.j), modifiers: [.option])
                case .focusDrawerPaneDown:
                    .init(key: .character(.k), modifiers: [.option])
                case .focusDrawerPaneRight:
                    .init(key: .character(.l), modifiers: [.option])
                default:
                    .init(key: .character(.j), modifiers: [.option])
                }
            return CommandSpec(
                command: self,
                displayShortcutTrigger: displayShortcutTrigger,
                label: "Move Drawer Focus",
                icon: "arrow.up.left.and.arrow.down.right",
                helpText: "Move selection within the active drawer",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane, .hasFocusedDrawerPane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .detachDrawerPane:
            return CommandSpec(
                command: self,
                label: "Detach Drawer Pane",
                icon: "rectangle.portrait.and.arrow.right",
                helpText: "Promote the selected drawer pane into the main layout",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane, .hasFocusedDrawerPane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane,
                isHiddenInCommandBar: true
            )
        case .addDrawerPane:
            return CommandSpec(
                command: self,
                shortcut: .addDrawerPane,
                label: "Add Drawer Pane",
                icon: "rectangle.bottomhalf.inset.filled",
                helpText: "Add a drawer pane to the active pane",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .toggleDrawer:
            return CommandSpec(
                command: self,
                shortcut: .toggleDrawer,
                label: "Toggle Drawer",
                icon: "rectangle.expand.vertical",
                helpText: "Expand or collapse the active pane drawer",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .navigateDrawerPane:
            return CommandSpec(
                command: self,
                label: "Switch Drawer Pane",
                icon: "arrow.down.to.line",
                helpText: "Switch to a pane inside the active drawer",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane, .hasDrawerPanes],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .closeDrawerPane:
            return CommandSpec(
                command: self,
                label: "Close Drawer Pane",
                icon: "xmark.rectangle.portrait",
                helpText: "Close a pane inside the active drawer",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane, .hasDrawerPanes],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .addRepo:
            return CommandSpec(
                command: self,
                shortcut: .addRepo,
                label: "Add Repo",
                icon: "folder.badge.plus",
                helpText: "Open a repository worktree directly in a new tab",
                commandBarGroupName: "Repo",
                commandBarGroupPriority: CommandBarGroupPriority.repo,
                isHiddenInCommandBar: true
            )
        case .addFolder:
            return CommandSpec(
                command: self,
                shortcut: .addFolder,
                label: "Watch Folder",
                icon: "folder.fill.badge.plus",
                helpText: "Watch a folder and scan it for repositories",
                commandBarGroupName: "Repo",
                commandBarGroupPriority: CommandBarGroupPriority.repo
            )
        case .removeRepo:
            return CommandSpec(
                command: self,
                label: "Remove Repo",
                icon: "folder.badge.minus",
                helpText: "Remove a repository from the workspace",
                appliesTo: [.repo],
                commandBarGroupName: "Repo",
                commandBarGroupPriority: CommandBarGroupPriority.repo
            )
        case .openWorktree:
            return worktreeDefinition(
                label: "Open Worktree",
                icon: "terminal",
                helpText: "Open a worktree in a tab"
            )
        case .openWorktreeInPane:
            return worktreeDefinition(
                label: "Open Worktree in Pane",
                icon: "rectangle.split.2x1",
                helpText: "Open a worktree in a split pane"
            )
        case .toggleManagementLayer:
            return CommandSpec(
                command: self,
                shortcut: .toggleManagementLayer,
                label: "Manage Workspace",
                icon: "rectangle.split.2x2",
                helpText: "Toggle workspace management mode",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .managementLayerFocusLeft:
            return managementDefinition(
                shortcut: .managementLayerFocusLeft,
                label: "Management Focus Left",
                icon: "arrow.left",
                helpText: "Move focus left in management mode"
            )
        case .managementLayerFocusRight:
            return managementDefinition(
                shortcut: .managementLayerFocusRight,
                label: "Management Focus Right",
                icon: "arrow.right",
                helpText: "Move focus right in management mode"
            )
        case .managementLayerEnterDrawer:
            return CommandSpec(
                command: self,
                label: "Management Enter Drawer",
                icon: "arrow.down",
                helpText: "Enter or expand the current drawer in management mode",
                requiresManagementLayer: true,
                isHiddenInCommandBar: true
            )
        case .managementLayerExitDrawer:
            return managementDefinition(
                shortcut: .managementLayerExitDrawer,
                label: "Management Exit Drawer",
                icon: "arrow.up",
                helpText: "Collapse the current drawer in management mode"
            )
        case .managementLayerOpenDrawer:
            return managementDefinition(
                shortcut: .managementLayerOpenDrawer,
                label: "Management Open Drawer",
                icon: "rectangle.expand.vertical",
                helpText: "Open the current drawer in management mode"
            )
        case .managementLayerCreateTerminal:
            return managementDefinition(
                shortcut: .managementLayerCreateTerminal,
                label: "Management Create Terminal",
                icon: "plus.square",
                helpText: "Create a terminal in the current management-mode context"
            )
        case .managementLayerCreateBrowser:
            return managementDefinition(
                shortcut: .managementLayerCreateBrowser,
                label: "Management Create Browser",
                icon: "globe",
                helpText: "Create a browser in the current management-mode context"
            )
        case .managementLayerExit:
            return managementDefinition(
                shortcut: .managementLayerExit,
                label: "Management Exit Mode",
                icon: "rectangle.split.2x2.fill",
                helpText: "Exit management mode"
            )
        case .toggleSidebar:
            return CommandSpec(
                command: self,
                shortcut: .toggleSidebar,
                label: "Toggle Sidebar",
                icon: "sidebar.left",
                helpText: "Show or hide the sidebar",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .newFloatingTerminal:
            return CommandSpec(
                command: self,
                label: "New Floating Terminal",
                icon: "terminal.fill",
                helpText: "Open a new floating terminal",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .newWindow:
            return CommandSpec(
                command: self,
                shortcut: .newWindow,
                label: "New Window",
                icon: "macwindow.badge.plus",
                helpText: "Open a new application window",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window,
                isHiddenInCommandBar: true
            )
        case .closeWindow:
            return CommandSpec(
                command: self,
                shortcut: .closeWindow,
                label: "Close Window",
                icon: "xmark.rectangle",
                helpText: "Close the current application window",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window,
                isHiddenInCommandBar: true
            )
        case .showCommandBarEverything:
            return CommandSpec(
                command: self,
                shortcut: .showCommandBarEverything,
                label: "Quick Find",
                icon: "magnifyingglass",
                helpText: "Open quick find",
                commandBarGroupName: "Commands",
                commandBarGroupPriority: CommandBarGroupPriority.miscellaneous,
                isHiddenInCommandBar: true
            )
        case .showCommandBarCommands:
            return CommandSpec(
                command: self,
                shortcut: .showCommandBarCommands,
                label: "Command Palette",
                icon: "command",
                helpText: "Open the command palette",
                commandBarGroupName: "Commands",
                commandBarGroupPriority: CommandBarGroupPriority.miscellaneous,
                isHiddenInCommandBar: true
            )
        case .showCommandBarPanes:
            return CommandSpec(
                command: self,
                shortcut: .showCommandBarPanes,
                label: "Go to Pane",
                icon: "terminal",
                helpText: "Open the pane picker",
                commandBarGroupName: "Commands",
                commandBarGroupPriority: CommandBarGroupPriority.miscellaneous,
                isHiddenInCommandBar: true
            )
        case .showCommandBarRepos:
            return CommandSpec(
                command: self,
                shortcut: .newTab,
                label: "New Tab or Worktree",
                icon: "folder",
                helpText: "Open the repo and worktree picker",
                commandBarGroupName: "Commands",
                commandBarGroupPriority: CommandBarGroupPriority.miscellaneous,
                isHiddenInCommandBar: true
            )
        case .openWebview:
            return CommandSpec(
                command: self,
                label: "Open New Webview Tab",
                icon: "globe",
                helpText: "Open a new webview tab",
                commandBarGroupName: "Webview",
                commandBarGroupPriority: CommandBarGroupPriority.webview
            )
        case .signInGitHub:
            return CommandSpec(
                command: self,
                label: "Sign in to GitHub",
                icon: "person.badge.key",
                helpText: "Start GitHub sign-in",
                commandBarGroupName: "Auth",
                commandBarGroupPriority: CommandBarGroupPriority.auth,
                isHiddenInCommandBar: true
            )
        case .signInGoogle:
            return CommandSpec(
                command: self,
                label: "Sign in to Google",
                icon: "person.badge.key",
                helpText: "Start Google sign-in",
                commandBarGroupName: "Auth",
                commandBarGroupPriority: CommandBarGroupPriority.auth,
                isHiddenInCommandBar: true
            )
        case .filterSidebar:
            return CommandSpec(
                command: self,
                shortcut: .filterSidebar,
                label: "Filter Sidebar",
                icon: "magnifyingglass",
                helpText: "Filter items in the sidebar",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .openNewTerminalInTab:
            return worktreeDefinition(
                label: "Open Terminal in New Tab",
                icon: "terminal.fill",
                helpText: "Open a worktree in a fresh terminal tab"
            )
        }
    }

    private func hiddenTabSelectionDefinition(index: Int) -> CommandSpec {
        CommandSpec(
            command: self,
            shortcut: selectTabShortcut(index: index),
            label: "Select Tab \(index)",
            helpText: "Select tab \(index)",
            visibleWhen: [.hasActiveTab],
            commandBarGroupPriority: CommandBarGroupPriority.miscellaneous,
            isHiddenInCommandBar: true
        )
    }

    private func focusDefinition(label: String, icon: String, helpText: String) -> CommandSpec {
        CommandSpec(
            command: self,
            label: label,
            icon: icon,
            helpText: helpText,
            visibleWhen: [.hasActiveTab, .hasMultiplePanes],
            commandBarGroupName: "Focus",
            commandBarGroupPriority: CommandBarGroupPriority.focus
        )
    }

    private func arrangementDefinition(label: String, icon: String, helpText: String) -> CommandSpec {
        CommandSpec(
            command: self,
            label: label,
            icon: icon,
            helpText: helpText,
            appliesTo: [.tab],
            visibleWhen: [.hasActiveTab, .hasArrangements],
            commandBarGroupName: "Tab",
            commandBarGroupPriority: CommandBarGroupPriority.tab
        )
    }

    private func worktreeDefinition(label: String, icon: String, helpText: String) -> CommandSpec {
        CommandSpec(
            command: self,
            label: label,
            icon: icon,
            helpText: helpText,
            appliesTo: [.worktree],
            commandBarGroupName: "Repo",
            commandBarGroupPriority: CommandBarGroupPriority.repo
        )
    }

    private func managementDefinition(shortcut: AppShortcut, label: String, icon: String, helpText: String)
        -> CommandSpec
    {
        CommandSpec(
            command: self,
            shortcut: shortcut,
            label: label,
            icon: icon,
            helpText: helpText,
            requiresManagementLayer: true,
            isHiddenInCommandBar: true
        )
    }

    private func selectTabShortcut(index: Int) -> AppShortcut {
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
