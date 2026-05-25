import Foundation

// MARK: - AppCommand Helpers

extension AppCommand {
    private enum CommandBarGroupPriority {
        static let terminal = 0
        static let pane = 1
        static let focus = 2
        static let tab = 3
        static let repo = 4
        static let window = 5
        static let webview = 6
        static let auth = 7
        static let miscellaneous = 8
    }

    /// Ordered array of tab selection commands (⌘1 through ⌘9)
    static let selectTabCommands: [AppCommand] = [
        .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
        .selectTab6, .selectTab7, .selectTab8, .selectTab9,
    ]

    static let focusPaneCommands: [AppCommand] = [
        .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
        .focusPane6, .focusPane7, .focusPane8, .focusPane9,
    ]

    static let focusDrawerPaneCommands: [AppCommand] = [
        .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4, .focusDrawerPane5,
        .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8, .focusDrawerPane9,
    ]

    var definition: CommandSpec {
        switch self {
        case .closeTab:
            return CommandSpec(
                command: self,
                shortcut: .closeTab,
                label: "Close Tab",
                icon: .system(.xmark),
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
                icon: .system(.rectangleSplit3x1),
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
                icon: .system(.pencil),
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
                icon: .system(.terminal),
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
                icon: .system(.plusSquare),
                helpText: "Create a new terminal tab",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .undoCloseTab:
            return CommandSpec(
                command: self,
                shortcut: .undoCloseTab,
                label: "Undo Close Tab",
                icon: .system(.arrowUturnBackward),
                helpText: "Restore the most recently closed tab",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .selectTab:
            return CommandSpec(
                command: self,
                label: "Select Tab",
                icon: .system(.rectangleStack),
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
                icon: .system(.chevronRight),
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
                icon: .system(.chevronLeft),
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
                icon: .system(.xmarkSquare),
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
                icon: .system(.arrowUpRightSquare),
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
                icon: .system(.arrowLeftAndRightSquare),
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
                icon: .system(.scope),
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
                icon: .system(.arrowDownToLine),
                helpText: "Scroll the active terminal pane to the bottom",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane, .paneIsTerminal],
                commandBarGroupName: "Terminal",
                commandBarGroupPriority: CommandBarGroupPriority.terminal
            )
        case .scrollPageUp:
            return CommandSpec(
                command: self,
                shortcut: .scrollPageUp,
                label: "Page Up",
                icon: .system(.arrowUp),
                helpText: "Scroll the active terminal pane up by one page",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane, .paneIsTerminal],
                commandBarGroupName: "Terminal",
                commandBarGroupPriority: CommandBarGroupPriority.terminal
            )
        case .jumpToPreviousPrompt:
            return CommandSpec(
                command: self,
                shortcut: .jumpToPreviousPrompt,
                label: "Previous Prompt",
                icon: .system(.arrowUp),
                helpText: "Jump to the previous shell prompt in terminal scrollback",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane, .paneIsTerminal],
                commandBarGroupName: "Terminal",
                commandBarGroupPriority: CommandBarGroupPriority.terminal
            )
        case .jumpToNextPrompt:
            return CommandSpec(
                command: self,
                shortcut: .jumpToNextPrompt,
                label: "Next Prompt",
                icon: .system(.arrowDown),
                helpText: "Jump to the next shell prompt in terminal scrollback",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane, .paneIsTerminal],
                commandBarGroupName: "Terminal",
                commandBarGroupPriority: CommandBarGroupPriority.terminal
            )
        case .splitRight:
            return CommandSpec(
                command: self,
                label: "Split Right",
                icon: .system(.rectangleSplit1x2),
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
                icon: .system(.rectangleSplit1x2),
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
                icon: .system(.equalSquare),
                helpText: "Reset all pane sizes in the active tab to equal widths",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab, .hasMultiplePanes],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .focusPaneLeft:
            return focusDefinition(
                label: "Focus Pane Left",
                icon: .system(.arrowLeft),
                helpText: "Move focus to the pane on the left"
            )
        case .focusPaneRight:
            return focusDefinition(
                label: "Focus Pane Right",
                icon: .system(.arrowRight),
                helpText: "Move focus to the pane on the right"
            )
        case .focusPaneUp:
            return focusDefinition(
                label: "Focus Pane Up",
                icon: .system(.arrowUp),
                helpText: "Move focus to the pane above"
            )
        case .focusPaneDown:
            return focusDefinition(
                label: "Focus Pane Down",
                icon: .system(.arrowDown),
                helpText: "Move focus to the pane below"
            )
        case .focusNextPane:
            return focusDefinition(
                label: "Focus Next Pane",
                icon: .system(.arrowRightCircle),
                helpText: "Move focus to the next pane"
            )
        case .focusPrevPane:
            return focusDefinition(
                label: "Focus Previous Pane",
                icon: .system(.arrowLeftCircle),
                helpText: "Move focus to the previous pane"
            )
        case .focusPane1:
            return hiddenFocusPaneDefinition(index: 1)
        case .focusPane2:
            return hiddenFocusPaneDefinition(index: 2)
        case .focusPane3:
            return hiddenFocusPaneDefinition(index: 3)
        case .focusPane4:
            return hiddenFocusPaneDefinition(index: 4)
        case .focusPane5:
            return hiddenFocusPaneDefinition(index: 5)
        case .focusPane6:
            return hiddenFocusPaneDefinition(index: 6)
        case .focusPane7:
            return hiddenFocusPaneDefinition(index: 7)
        case .focusPane8:
            return hiddenFocusPaneDefinition(index: 8)
        case .focusPane9:
            return hiddenFocusPaneDefinition(index: 9)
        case .toggleSplitZoom:
            return CommandSpec(
                command: self,
                label: "Toggle Split Zoom",
                icon: .system(.plusMagnifyingglass),
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
                icon: .system(.minusCircle),
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
                icon: .system(.arrowUpLeftAndArrowDownRight),
                helpText: "Expand a minimized pane back into the layout",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .switchArrangement:
            return arrangementDefinition(
                shortcut: .showArrangementPanel,
                label: "Show Arrangements",
                icon: .system(.rectangle3Group),
                helpText: "Show arrangements for the active tab"
            )
        case .previousArrangement:
            return CommandSpec(
                command: self,
                shortcut: .previousArrangement,
                label: "Previous Arrangement",
                icon: .system(.chevronLeft),
                helpText: "Switch the active tab to the previous arrangement",
                visibleWhen: [.hasActiveTab, .hasArrangements],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .nextArrangement:
            return CommandSpec(
                command: self,
                shortcut: .nextArrangement,
                label: "Next Arrangement",
                icon: .system(.chevronRight),
                helpText: "Switch the active tab to the next arrangement",
                visibleWhen: [.hasActiveTab, .hasArrangements],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .cycleArrangement:
            return CommandSpec(
                command: self,
                label: "Cycle Arrangement",
                icon: .system(.rectangle3Group),
                helpText: "Switch to the next arrangement in the active tab",
                visibleWhen: [.hasActiveTab, .hasArrangements],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab,
                isHiddenInCommandBar: true
            )
        case .saveArrangement:
            return CommandSpec(
                command: self,
                label: "Save Arrangement As...",
                icon: .system(.rectangle3GroupFill),
                helpText: "Save the current tab layout as a named arrangement",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .deleteArrangement:
            return arrangementDefinition(
                label: "Delete Arrangement",
                icon: .system(.rectangle3GroupBubble),
                helpText: "Delete a saved arrangement from the active tab"
            )
        case .renameArrangement:
            return arrangementDefinition(
                label: "Rename Arrangement",
                icon: .system(.pencil),
                helpText: "Rename a saved arrangement in the active tab"
            )
        case .enterDrawer:
            return CommandSpec(
                command: self,
                label: "Enter Drawer",
                icon: .system(.rectangleBottomhalfFilled),
                helpText: "Open the active pane and focus its selected pane",
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
                icon: .system(.arrowUpLeftAndArrowDownRight),
                helpText: "Move selection within the active pane",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane, .hasFocusedDrawerPane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .focusDrawerPane1:
            return hiddenFocusDrawerPaneDefinition(index: 1)
        case .focusDrawerPane2:
            return hiddenFocusDrawerPaneDefinition(index: 2)
        case .focusDrawerPane3:
            return hiddenFocusDrawerPaneDefinition(index: 3)
        case .focusDrawerPane4:
            return hiddenFocusDrawerPaneDefinition(index: 4)
        case .focusDrawerPane5:
            return hiddenFocusDrawerPaneDefinition(index: 5)
        case .focusDrawerPane6:
            return hiddenFocusDrawerPaneDefinition(index: 6)
        case .focusDrawerPane7:
            return hiddenFocusDrawerPaneDefinition(index: 7)
        case .focusDrawerPane8:
            return hiddenFocusDrawerPaneDefinition(index: 8)
        case .focusDrawerPane9:
            return hiddenFocusDrawerPaneDefinition(index: 9)
        case .detachDrawerPane:
            return CommandSpec(
                command: self,
                label: "Detach Drawer Pane",
                icon: .system(.rectanglePortraitAndArrowRight),
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
                icon: .system(.rectangleBottomhalfInsetFilled),
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
                icon: .system(.rectangleExpandVertical),
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
                icon: .system(.arrowDownToLine),
                helpText: "Switch to a pane inside the active pane",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane, .hasDrawerPanes],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .closeDrawerPane:
            return CommandSpec(
                command: self,
                label: "Close Drawer Pane",
                icon: .system(.xmarkRectanglePortrait),
                helpText: "Close a pane inside the active pane",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane, .hasDrawerPanes],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .watchFolder:
            return CommandSpec(
                command: self,
                label: "Watch Folder",
                icon: .system(.folderFillBadgePlus),
                helpText: "Watch a folder and scan it for repositories",
                commandBarGroupName: "Repo",
                commandBarGroupPriority: CommandBarGroupPriority.repo
            )
        case .removeRepo:
            return CommandSpec(
                command: self,
                label: "Remove Repo",
                icon: .system(.folderBadgeMinus),
                helpText: "Remove a repository from the workspace",
                appliesTo: [.repo],
                commandBarGroupName: "Repo",
                commandBarGroupPriority: CommandBarGroupPriority.repo
            )
        case .openWorktree:
            return worktreeDefinition(
                label: "Open Worktree",
                icon: .system(.terminal),
                helpText: "Open a worktree in a tab"
            )
        case .openWorktreeInPane:
            return worktreeDefinition(
                label: "Open Worktree in Pane",
                icon: .system(.rectangleSplit2x1),
                helpText: "Open a worktree in a split pane"
            )
        case .openPaneLocationInBookmarkedEditor:
            return CommandSpec(
                command: self,
                shortcut: .openPaneLocationInBookmarkedEditor,
                label: "Open Pane Location in Bookmarked Editor",
                icon: .system(.chevronLeftForwardslashChevronRight),
                helpText: "Open the selected pane location in the bookmarked editor",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .openPaneLocationInFinder:
            return CommandSpec(
                command: self,
                shortcut: .openPaneLocationInFinder,
                label: "Open Pane Location in Finder",
                icon: .system(.finder),
                helpText: "Open the selected pane location in Finder",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .openPaneLocationInEditorMenu:
            return CommandSpec(
                command: self,
                shortcut: .openPaneLocationInEditorMenu,
                label: "Open In Menu",
                icon: .system(.chevronUpChevronDown),
                helpText: "Open the editor chooser for the selected pane",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .toggleManagementLayer:
            return CommandSpec(
                command: self,
                shortcut: .toggleManagementLayer,
                label: "Manage Workspace",
                icon: .system(.rectangleSplit2x2),
                helpText: "Toggle workspace management mode",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .managementLayerFocusLeft:
            return managementDefinition(
                shortcut: .managementLayerFocusLeft,
                label: "Management Focus Left",
                icon: .system(.arrowLeft),
                helpText: "Move focus left in management mode"
            )
        case .managementLayerFocusRight:
            return managementDefinition(
                shortcut: .managementLayerFocusRight,
                label: "Management Focus Right",
                icon: .system(.arrowRight),
                helpText: "Move focus right in management mode"
            )
        case .managementLayerEnterDrawer:
            return CommandSpec(
                command: self,
                shortcut: .managementLayerEnterDrawer,
                label: "Management Enter Drawer",
                icon: .system(.arrowDown),
                helpText: "Enter or expand the current drawer in management mode",
                requiresManagementLayer: true,
                isHiddenInCommandBar: true
            )
        case .managementLayerExitDrawer:
            return managementDefinition(
                shortcut: .managementLayerExitDrawer,
                label: "Management Exit Drawer",
                icon: .system(.arrowUp),
                helpText: "Collapse the current drawer in management mode"
            )
        case .managementLayerOpenDrawer:
            return managementDefinition(
                shortcut: .managementLayerOpenDrawer,
                label: "Management Open Drawer",
                icon: .system(.rectangleExpandVertical),
                helpText: "Open the current drawer in management mode"
            )
        case .managementLayerCreateTerminal:
            return managementDefinition(
                shortcut: .managementLayerCreateTerminal,
                label: "Management Create Terminal",
                icon: .system(.plusSquare),
                helpText: "Create a terminal in the current management-mode context"
            )
        case .managementLayerCreateBrowser:
            return managementDefinition(
                shortcut: .managementLayerCreateBrowser,
                label: "Management Create Browser",
                icon: .system(.globe),
                helpText: "Create a browser in the current management-mode context"
            )
        case .managementLayerExit:
            return managementDefinition(
                shortcut: .managementLayerExit,
                label: "Management Exit Mode",
                icon: .system(.rectangleSplit2x2Fill),
                helpText: "Exit management mode"
            )
        case .toggleSidebar:
            return CommandSpec(
                command: self,
                shortcut: .toggleSidebar,
                label: "Toggle Sidebar",
                icon: .system(.sidebarLeft),
                helpText: "Show or hide the sidebar",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .showInboxNotifications:
            return CommandSpec(
                command: self,
                shortcut: .showInboxNotifications,
                label: "Toggle Inbox",
                icon: .system(.bell),
                helpText: "Show or hide the notification inbox in the sidebar",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .toggleInboxNotificationSort:
            return CommandSpec(
                command: self,
                label: "Toggle Inbox Sort Order",
                icon: .system(.arrowUpArrowDown),
                helpText: "Switch the inbox between newest-first and oldest-first order",
                commandBarGroupName: "Inbox",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .clearReadInboxNotifications:
            return CommandSpec(
                command: self,
                label: "Clear Read Inbox Notifications",
                icon: .system(.deleteLeft),
                helpText: "Remove read notifications from the inbox history",
                commandBarGroupName: "Inbox",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .clearAllInboxNotifications:
            return CommandSpec(
                command: self,
                label: "Clear All Inbox Notifications",
                icon: .system(.deleteLeft),
                helpText: "Remove every notification from the inbox history",
                commandBarGroupName: "Inbox",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .showPaneInboxNotifications:
            return CommandSpec(
                command: self,
                shortcut: .showPaneInboxNotifications,
                label: "Toggle Pane Inbox",
                icon: .system(.bellBadge),
                helpText: "Show notifications for the active pane and its drawer children",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .clearPaneInboxNotifications:
            return CommandSpec(
                command: self,
                label: "Clear Pane Inbox",
                icon: .system(.deleteLeft),
                helpText: "Clear notifications for the active pane and its drawer children",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .showWorktreeSidebar:
            return CommandSpec(
                command: self,
                shortcut: .showWorktreeSidebar,
                label: "Toggle Worktrees",
                icon: .system(.sidebarLeft),
                helpText: "Show or hide the repo explorer in the sidebar",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .newFloatingTerminal:
            return CommandSpec(
                command: self,
                label: "New Floating Terminal",
                icon: .system(.terminalFill),
                helpText: "Open a new floating terminal",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .newWindow:
            return CommandSpec(
                command: self,
                shortcut: .newWindow,
                label: "New Window",
                icon: .system(.macwindowBadgePlus),
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
                icon: .system(.xmarkRectangle),
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
                icon: .system(.magnifyingglass),
                helpText: "Open quick find",
                commandBarGroupName: "Commands",
                commandBarGroupPriority: CommandBarGroupPriority.miscellaneous
            )
        case .showCommandBarCommands:
            return CommandSpec(
                command: self,
                shortcut: .showCommandBarCommands,
                label: "Command Palette",
                icon: .system(.command),
                helpText: "Open the command palette",
                commandBarGroupName: "Commands",
                commandBarGroupPriority: CommandBarGroupPriority.miscellaneous
            )
        case .showCommandBarPanes:
            return CommandSpec(
                command: self,
                shortcut: .showCommandBarPanes,
                label: "Go to Pane",
                icon: .system(.terminal),
                helpText: "Open the pane picker",
                commandBarGroupName: "Commands",
                commandBarGroupPriority: CommandBarGroupPriority.miscellaneous
            )
        case .showCommandBarRepos:
            return CommandSpec(
                command: self,
                shortcut: .newTab,
                label: "New Tab or Worktree",
                icon: .system(.folder),
                helpText: "Open the repo and worktree picker",
                commandBarGroupName: "Commands",
                commandBarGroupPriority: CommandBarGroupPriority.miscellaneous
            )
        case .openWebview:
            return CommandSpec(
                command: self,
                label: "Open New Webview Tab",
                icon: .system(.globe),
                helpText: "Open a new webview tab",
                commandBarGroupName: "Webview",
                commandBarGroupPriority: CommandBarGroupPriority.webview
            )
        case .signInGitHub:
            return CommandSpec(
                command: self,
                label: "Sign in to GitHub",
                icon: .system(.personBadgeKey),
                helpText: "Start GitHub sign-in",
                commandBarGroupName: "Auth",
                commandBarGroupPriority: CommandBarGroupPriority.auth,
                isHiddenInCommandBar: true
            )
        case .signInGoogle:
            return CommandSpec(
                command: self,
                label: "Sign in to Google",
                icon: .system(.personBadgeKey),
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
                icon: .system(.magnifyingglass),
                helpText: "Filter items in the sidebar",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .openNewTerminalInTab:
            return worktreeDefinition(
                label: "Open Terminal in New Tab",
                icon: .system(.terminalFill),
                helpText: "Open a worktree in a fresh terminal tab"
            )
        }
    }

    private func hiddenTabSelectionDefinition(index: Int) -> CommandSpec {
        CommandSpec(
            command: self,
            label: "Select Tab \(index)",
            icon: .system(.rectangleStack),
            helpText: "Select tab \(index)",
            visibleWhen: [.hasActiveTab],
            commandBarGroupPriority: CommandBarGroupPriority.miscellaneous,
            isHiddenInCommandBar: true
        )
    }

    private func hiddenFocusPaneDefinition(index: Int) -> CommandSpec {
        CommandSpec(
            command: self,
            shortcut: focusPaneShortcut(index: index),
            label: "Focus Pane \(index)",
            icon: .system(.rectangleSplit2x1),
            helpText: "Focus pane \(index)",
            visibleWhen: [.hasActiveTab],
            commandBarGroupName: "Focus",
            commandBarGroupPriority: CommandBarGroupPriority.focus,
            isHiddenInCommandBar: true
        )
    }

    private func hiddenFocusDrawerPaneDefinition(index: Int) -> CommandSpec {
        CommandSpec(
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

    private func focusDefinition(label: String, icon: CommandIcon, helpText: String) -> CommandSpec {
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

    private func arrangementDefinition(
        shortcut: AppShortcut? = nil,
        label: String,
        icon: CommandIcon,
        helpText: String
    ) -> CommandSpec {
        CommandSpec(
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

    private func worktreeDefinition(label: String, icon: CommandIcon, helpText: String) -> CommandSpec {
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

    private func managementDefinition(shortcut: AppShortcut, label: String, icon: CommandIcon, helpText: String)
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

    private func focusPaneShortcut(index: Int) -> AppShortcut {
        switch index {
        case 1: return .focusPane1
        case 2: return .focusPane2
        case 3: return .focusPane3
        case 4: return .focusPane4
        case 5: return .focusPane5
        case 6: return .focusPane6
        case 7: return .focusPane7
        case 8: return .focusPane8
        case 9: return .focusPane9
        default:
            preconditionFailure("Unsupported pane focus shortcut index \(index)")
        }
    }

}
