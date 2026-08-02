import Foundation

// MARK: - AppCommand Helpers

extension AppCommand {
    package var definition: AppCommandSpec {
        switch self {
        case .closeTab:
            return AppCommandSpec(
                command: self,
                shortcut: .closeTab,
                label: "Close Tab",
                icon: .system(.xmark),
                helpText: "Close the active tab",
                surfacePolicy: .exposed([.commandBar, .mainMenu, .contextMenu, .inlineControl]),
                targeting: .contextualAndTargeted([.tab], preferredInvocation: .targetSelection),
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .breakUpTab:
            return AppCommandSpec(
                command: self,
                label: "Split Tab Into Individuals",
                icon: .system(.rectangleSplit3x1),
                helpText: "Split each visible pane in the active tab into its own tab",
                surfacePolicy: .exposed([.commandBar, .contextMenu]),
                targeting: .contextualAndTargeted([.tab], preferredInvocation: .contextual),
                visibleWhen: [.hasActiveTab, .hasMultiplePanes],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .renameTab:
            return AppCommandSpec(
                command: self,
                label: "Rename Tab...",
                icon: .system(.pencil),
                helpText: "Rename the current tab",
                surfacePolicy: .exposed([.commandBar, .contextMenu]),
                targeting: .contextualAndTargeted([.tab], preferredInvocation: .targetSelection),
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .newTerminalInTab:
            return AppCommandSpec(
                command: self,
                label: "Add Terminal to Tab",
                icon: .system(.terminal),
                helpText: "Add a new terminal to the active tab",
                surfacePolicy: .exposed([.commandBar, .contextMenu]),
                targeting: .contextualAndTargeted([.tab], preferredInvocation: .targetSelection),
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .newTab:
            return AppCommandSpec(
                command: self,
                label: "New Tab",
                icon: .system(.plusSquare),
                helpText: "Create a new terminal tab",
                surfacePolicy: .exposed([.commandBar, .mainMenu, .contextMenu, .toolbar(.app)]),
                targeting: .contextual,
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .undoCloseTab:
            return AppCommandSpec(
                command: self,
                shortcut: .undoCloseTab,
                label: "Undo Close Tab",
                icon: .system(.arrowUturnBackward),
                helpText: "Restore the most recently closed tab",
                surfacePolicy: .exposed([.commandBar, .mainMenu]),
                targeting: .contextual,
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .selectTab:
            return AppCommandSpec(
                command: self,
                label: "Select Tab",
                icon: .system(.rectangleStack),
                helpText: "Select a specific tab",
                surfacePolicy: .notPresented,
                targeting: .targeted([.tab]),
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab,
            )
        case .nextTab:
            return AppCommandSpec(
                command: self,
                shortcut: .nextTab,
                label: "Next Tab",
                icon: .system(.chevronRight),
                helpText: "Move to the next tab",
                surfacePolicy: .exposed([.commandBar]),
                targeting: .contextual,
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .prevTab:
            return AppCommandSpec(
                command: self,
                shortcut: .prevTab,
                label: "Previous Tab",
                icon: .system(.chevronLeft),
                helpText: "Move to the previous tab",
                surfacePolicy: .exposed([.commandBar]),
                targeting: .contextual,
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .selectTab1:
            return menuTabSelectionDefinition(index: 1)
        case .selectTab2:
            return menuTabSelectionDefinition(index: 2)
        case .selectTab3:
            return menuTabSelectionDefinition(index: 3)
        case .selectTab4:
            return menuTabSelectionDefinition(index: 4)
        case .selectTab5:
            return menuTabSelectionDefinition(index: 5)
        case .selectTab6:
            return menuTabSelectionDefinition(index: 6)
        case .selectTab7:
            return menuTabSelectionDefinition(index: 7)
        case .selectTab8:
            return menuTabSelectionDefinition(index: 8)
        case .selectTab9:
            return menuTabSelectionDefinition(index: 9)
        case .closePane:
            return AppCommandSpec(
                command: self,
                label: "Close Pane",
                icon: .system(.xmarkSquare),
                helpText: "Close the active pane",
                surfacePolicy: .exposed([.commandBar, .contextMenu, .inlineControl]),
                targeting: .contextualAndTargeted([.pane, .floatingTerminal], preferredInvocation: .targetSelection),
                requiresManagementLayer: true,
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .extractPaneToTab:
            return AppCommandSpec(
                command: self,
                label: "Move Pane to New Tab",
                icon: .system(.arrowUpRightSquare),
                helpText: "Move the active pane into a new tab",
                surfacePolicy: .exposed([.commandBar, .contextMenu]),
                targeting: .contextualAndTargeted([.pane, .floatingTerminal], preferredInvocation: .targetSelection),
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .movePaneToTab:
            return AppCommandSpec(
                command: self,
                label: "Move Pane to Existing Tab",
                icon: .system(.arrowLeftArrowRight),
                helpText: "Move the active pane into another existing tab",
                surfacePolicy: .exposed([.commandBar, .contextMenu, .inlineControl]),
                targeting: .targeted([.pane, .tab]),
                requiresManagementLayer: true,
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .focusPane:
            return AppCommandSpec(
                command: self,
                label: "Focus Pane",
                icon: .system(.scope),
                helpText: "Focus a specific pane",
                surfacePolicy: .notPresented,
                targeting: .targeted([.pane, .floatingTerminal]),
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane,
            )
        case .scrollToBottom:
            return AppCommandSpec(
                command: self,
                shortcut: .scrollToBottom,
                label: "Scroll to Bottom",
                icon: .system(.arrowDownToLine),
                helpText: "Scroll the active terminal pane to the bottom",
                surfacePolicy: .exposed([.commandBar, .inlineControl]),
                targeting: .contextualAndTargeted([.pane, .floatingTerminal], preferredInvocation: .contextual),
                visibleWhen: [.hasActivePane, .paneIsTerminal],
                commandBarGroupName: "Terminal",
                commandBarGroupPriority: CommandBarGroupPriority.terminal
            )
        case .scrollPageUp:
            return AppCommandSpec(
                command: self,
                shortcut: .scrollPageUp,
                label: "Page Up",
                icon: .system(.arrowUp),
                helpText: "Scroll the active terminal pane up by one page",
                surfacePolicy: .exposed([.commandBar]),
                targeting: .contextualAndTargeted([.pane, .floatingTerminal], preferredInvocation: .contextual),
                visibleWhen: [.hasActivePane, .paneIsTerminal],
                commandBarGroupName: "Terminal",
                commandBarGroupPriority: CommandBarGroupPriority.terminal
            )
        case .jumpToPreviousPrompt:
            return AppCommandSpec(
                command: self,
                shortcut: .jumpToPreviousPrompt,
                label: "Previous Prompt",
                icon: .system(.arrowUp),
                helpText: "Jump to the previous shell prompt in terminal scrollback",
                surfacePolicy: .exposed([.commandBar]),
                targeting: .contextualAndTargeted([.pane, .floatingTerminal], preferredInvocation: .contextual),
                visibleWhen: [.hasActivePane, .paneIsTerminal],
                commandBarGroupName: "Terminal",
                commandBarGroupPriority: CommandBarGroupPriority.terminal
            )
        case .jumpToNextPrompt:
            return AppCommandSpec(
                command: self,
                shortcut: .jumpToNextPrompt,
                label: "Next Prompt",
                icon: .system(.arrowDown),
                helpText: "Jump to the next shell prompt in terminal scrollback",
                surfacePolicy: .exposed([.commandBar]),
                targeting: .contextualAndTargeted([.pane, .floatingTerminal], preferredInvocation: .contextual),
                visibleWhen: [.hasActivePane, .paneIsTerminal],
                commandBarGroupName: "Terminal",
                commandBarGroupPriority: CommandBarGroupPriority.terminal
            )
        case .splitRight:
            return AppCommandSpec(
                command: self,
                label: "Split Right",
                icon: .system(.rectangleSplit1x2),
                helpText: "Split the active pane to the right",
                surfacePolicy: .exposed([.commandBar, .contextMenu, .inlineControl]),
                targeting: .contextualAndTargeted(
                    [.pane, .tab],
                    preferredInvocation: .contextual
                ),
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .splitLeft:
            return AppCommandSpec(
                command: self,
                label: "Split Left",
                icon: .system(.rectangleSplit1x2),
                helpText: "Split the active pane to the left",
                surfacePolicy: .exposed([.commandBar, .contextMenu]),
                targeting: .contextualAndTargeted(
                    [.tab],
                    preferredInvocation: .contextual
                ),
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .equalizePanes:
            return AppCommandSpec(
                command: self,
                label: "Equalize Panes",
                icon: .system(.equalSquare),
                helpText: "Reset all pane sizes in the active tab to equal widths",
                surfacePolicy: .exposed([.commandBar, .contextMenu]),
                targeting: .contextualAndTargeted(
                    [.tab],
                    preferredInvocation: .contextual
                ),
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
            return shortcutFocusPaneDefinition(index: 1)
        case .focusPane2:
            return shortcutFocusPaneDefinition(index: 2)
        case .focusPane3:
            return shortcutFocusPaneDefinition(index: 3)
        case .focusPane4:
            return shortcutFocusPaneDefinition(index: 4)
        case .focusPane5:
            return shortcutFocusPaneDefinition(index: 5)
        case .focusPane6:
            return shortcutFocusPaneDefinition(index: 6)
        case .focusPane7:
            return shortcutFocusPaneDefinition(index: 7)
        case .focusPane8:
            return shortcutFocusPaneDefinition(index: 8)
        case .focusPane9:
            return shortcutFocusPaneDefinition(index: 9)
        case .zoomPane:
            return AppCommandSpec(
                command: self,
                shortcut: .zoomPane,
                label: "Pane Zoom",
                icon: .system(.squareArrowTriangle4Outward),
                helpText: "Zoom the active pane",
                surfacePolicy: .exposed([.commandBar, .toolbar(.pane), .toolbar(.terminalZoom), .inlineControl]),
                targeting: .contextualAndTargeted([.pane], preferredInvocation: .contextual),
                visibleWhen: [.supportsTerminalZoom],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .minimizePane:
            return AppCommandSpec(
                command: self,
                label: "Minimize Pane",
                icon: .system(.minusCircle),
                helpText: "Minimize the active pane",
                surfacePolicy: .exposed([.commandBar, .inlineControl]),
                targeting: .contextualAndTargeted([.pane], preferredInvocation: .contextual),
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .expandPane:
            return AppCommandSpec(
                command: self,
                label: "Expand Pane",
                icon: .system(.arrowUpLeftAndArrowDownRight),
                helpText: "Expand a minimized pane back into the layout",
                surfacePolicy: .exposed([.commandBar, .contextMenu, .inlineControl]),
                targeting: .contextualAndTargeted([.pane], preferredInvocation: .contextual),
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .switchArrangement:
            return arrangementDefinition(
                shortcut: .showArrangementPanel,
                label: "Show Arrangements",
                icon: .system(.rectangle3Group),
                helpText: "Show arrangements for the active tab",
                surfacePolicy: .exposed([
                    .commandBar,
                    .toolbar(.app),
                    .inlineControl,
                ]),
                targeting: .contextualAndTargeted(
                    [.tab],
                    preferredInvocation: .targetSelection
                )
            )
        case .previousArrangement:
            return AppCommandSpec(
                command: self,
                shortcut: .previousArrangement,
                label: "Previous Arrangement",
                icon: .system(.chevronLeft),
                helpText: "Switch the active tab to the previous arrangement",
                surfacePolicy: .exposed([.commandBar]),
                targeting: .contextualAndTargeted([.tab], preferredInvocation: .contextual),
                visibleWhen: [.hasActiveTab, .hasArrangements],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .nextArrangement:
            return AppCommandSpec(
                command: self,
                shortcut: .nextArrangement,
                label: "Next Arrangement",
                icon: .system(.chevronRight),
                helpText: "Switch the active tab to the next arrangement",
                surfacePolicy: .exposed([.commandBar]),
                targeting: .contextualAndTargeted([.tab], preferredInvocation: .contextual),
                visibleWhen: [.hasActiveTab, .hasArrangements],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .cycleArrangement:
            return AppCommandSpec(
                command: self,
                label: "Cycle Arrangement",
                icon: .system(.rectangle3Group),
                helpText: "Switch to the next arrangement in the active tab",
                surfacePolicy: .notPresented,
                targeting: .contextual,
                visibleWhen: [.hasActiveTab, .hasArrangements],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab,
            )
        case .saveArrangement:
            return AppCommandSpec(
                command: self,
                label: "Save Arrangement As...",
                icon: .system(.rectangle3GroupFill),
                helpText: "Save the current tab layout as a named arrangement",
                surfacePolicy: .exposed([.commandBar, .contextMenu, .inlineControl]),
                targeting: .contextualAndTargeted([.tab], preferredInvocation: .contextual),
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .deleteArrangement:
            return arrangementDefinition(
                label: "Delete Arrangement",
                icon: .system(.rectangle3GroupBubble),
                helpText: "Delete a saved arrangement from the active tab",
                surfacePolicy: .exposed([.commandBar, .contextMenu]),
                targeting: .targeted([.tab])
            )
        case .renameArrangement:
            return arrangementDefinition(
                label: "Rename Arrangement",
                icon: .system(.pencil),
                helpText: "Rename a saved arrangement in the active tab",
                surfacePolicy: .exposed([.commandBar, .contextMenu, .inlineControl]),
                targeting: .targeted([.tab])
            )
        case .enterDrawer:
            return AppCommandSpec(
                command: self,
                label: "Enter Drawer",
                icon: .system(.rectangleBottomhalfFilled),
                helpText: "Open the active pane and focus its selected pane",
                surfacePolicy: .exposed([.commandBar]),
                targeting: .contextual,
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
            return AppCommandSpec(
                command: self,
                displayShortcutTrigger: displayShortcutTrigger,
                label: "Move Drawer Focus",
                icon: .system(.arrowUpLeftAndArrowDownRight),
                helpText: "Move selection within the active pane",
                surfacePolicy: .exposed([.commandBar]),
                targeting: .contextual,
                visibleWhen: [.hasActivePane, .hasFocusedDrawerPane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .focusDrawerPane1:
            return shortcutFocusDrawerPaneDefinition(index: 1)
        case .focusDrawerPane2:
            return shortcutFocusDrawerPaneDefinition(index: 2)
        case .focusDrawerPane3:
            return shortcutFocusDrawerPaneDefinition(index: 3)
        case .focusDrawerPane4:
            return shortcutFocusDrawerPaneDefinition(index: 4)
        case .focusDrawerPane5:
            return shortcutFocusDrawerPaneDefinition(index: 5)
        case .focusDrawerPane6:
            return shortcutFocusDrawerPaneDefinition(index: 6)
        case .focusDrawerPane7:
            return shortcutFocusDrawerPaneDefinition(index: 7)
        case .focusDrawerPane8:
            return shortcutFocusDrawerPaneDefinition(index: 8)
        case .focusDrawerPane9:
            return shortcutFocusDrawerPaneDefinition(index: 9)
        case .detachDrawerPane:
            return AppCommandSpec(
                command: self,
                label: "Detach Drawer Pane",
                icon: .system(.rectanglePortraitAndArrowRight),
                helpText: "Promote the selected drawer pane into the main layout",
                surfacePolicy: .exposed([.inlineControl]),
                targeting: .contextualAndTargeted([.pane], preferredInvocation: .contextual),
                visibleWhen: [.hasActivePane, .hasFocusedDrawerPane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane,
            )
        case .addDrawerPane:
            return AppCommandSpec(
                command: self,
                shortcut: .addDrawerPane,
                label: "Add Drawer Pane",
                icon: .system(.rectangleBottomhalfInsetFilled),
                helpText: "Add a drawer pane to the active pane",
                surfacePolicy: .exposed([.commandBar, .toolbar(.pane), .toolbar(.terminalZoom), .inlineControl]),
                targeting: .contextualAndTargeted([.pane, .floatingTerminal], preferredInvocation: .contextual),
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .toggleDrawer:
            return AppCommandSpec(
                command: self,
                shortcut: .toggleDrawer,
                label: "Toggle Drawer",
                icon: .system(.rectangleExpandVertical),
                helpText: "Expand or collapse the active pane drawer",
                surfacePolicy: .exposed([.commandBar, .toolbar(.pane), .toolbar(.terminalZoom)]),
                targeting: .contextualAndTargeted([.pane], preferredInvocation: .contextual),
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .navigateDrawerPane:
            return AppCommandSpec(
                command: self,
                label: "Switch Drawer Pane",
                icon: .system(.arrowDownToLine),
                helpText: "Switch to a pane inside the active pane",
                surfacePolicy: .exposed([.commandBar]),
                targeting: .contextualAndTargeted([.pane], preferredInvocation: .targetSelection),
                visibleWhen: [.hasActivePane, .hasDrawerPanes],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .closeDrawerPane:
            return AppCommandSpec(
                command: self,
                label: "Close Drawer Pane",
                icon: .system(.xmarkRectanglePortrait),
                helpText: "Close a pane inside the active pane",
                surfacePolicy: .exposed([.commandBar]),
                targeting: .contextual,
                visibleWhen: [.hasActivePane, .hasDrawerPanes],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .watchFolder:
            return AppCommandSpec(
                command: self,
                label: "Watch Folder",
                icon: .system(.folderFillBadgePlus),
                helpText: "Watch a folder and scan it for repositories",
                surfacePolicy: .exposed([.commandBar, .toolbar(.app), .inlineControl]),
                targeting: .contextual,
                commandBarGroupName: "Repo",
                commandBarGroupPriority: CommandBarGroupPriority.repo
            )
        case .removeRepo:
            return AppCommandSpec(
                command: self,
                label: "Remove Repo",
                icon: .system(.folderBadgeMinus),
                helpText: "Remove a repository from the workspace",
                surfacePolicy: .exposed([.commandBar]),
                targeting: .targeted([.repo]),
                commandBarGroupName: "Repo",
                commandBarGroupPriority: CommandBarGroupPriority.repo
            )
        case .addRepoFavorite:
            return repoFavoriteDefinition(
                label: "Add Favorite",
                icon: .bookmark,
                helpText: "Add favorite"
            )
        case .removeRepoFavorite:
            return repoFavoriteDefinition(
                label: "Remove Favorite",
                icon: .bookmarkFill,
                helpText: "Remove favorite"
            )
        case .openWorktree:
            return worktreeDefinition(
                label: "Open Worktree",
                icon: .system(.terminal),
                helpText: "Open a worktree in a tab",
                surfacePolicy: .exposed([.commandBar, .contextMenu, .inlineControl])
            )
        case .openWorktreeInPane:
            return worktreeDefinition(
                label: "Open Worktree in Pane",
                icon: .system(.rectangleSplit2x1),
                helpText: "Open a worktree in a split pane",
                surfacePolicy: .exposed([.commandBar, .contextMenu])
            )
        case .openPaneLocationInBookmarkedEditor:
            return AppCommandSpec(
                command: self,
                shortcut: .openPaneLocationInBookmarkedEditor,
                label: "Open Pane Location in Bookmarked Editor",
                icon: .system(.chevronLeftForwardslashChevronRight),
                helpText: "Open the selected pane location in the bookmarked editor",
                surfacePolicy: .exposed([.commandBar]),
                targeting: .contextual,
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .openPaneLocationInFinder:
            return AppCommandSpec(
                command: self,
                shortcut: .openPaneLocationInFinder,
                label: "Open Pane Location in Finder",
                icon: .system(.finder),
                helpText: "Open the selected pane location in Finder",
                surfacePolicy: .exposed([.commandBar, .toolbar(.pane), .toolbar(.terminalZoom)]),
                targeting: .contextualAndTargeted([.pane], preferredInvocation: .contextual),
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .openPaneLocationInEditorMenu:
            return AppCommandSpec(
                command: self,
                shortcut: .openPaneLocationInEditorMenu,
                label: "Open In Menu",
                icon: .system(.chevronUpChevronDown),
                helpText: "Open the editor chooser for the selected pane",
                surfacePolicy: .exposed([.commandBar, .toolbar(.pane), .toolbar(.terminalZoom)]),
                targeting: .contextualAndTargeted([.pane], preferredInvocation: .contextual),
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .editPaneNote:
            return AppCommandSpec(
                command: self,
                shortcut: .editPaneNote,
                label: "Edit Pane Note",
                icon: .system(.pencil),
                helpText: "Set a note for the current pane",
                surfacePolicy: .exposed([.commandBar]),
                targeting: .contextual,
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .copyCurrentPanePath:
            return AppCommandSpec(
                command: self,
                shortcut: .copyCurrentPanePath,
                label: "Copy Current Pane Path",
                icon: LocalActionSpec.copyPath.actionSpec.icon,
                helpText: "Copy the current pane path",
                surfacePolicy: .exposed([.commandBar, .toolbar(.pane), .toolbar(.terminalZoom)]),
                targeting: .contextualAndTargeted([.pane], preferredInvocation: .contextual),
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .toggleManagementLayer:
            return windowDefinition(
                shortcut: .toggleManagementLayer,
                label: "Manage Workspace",
                icon: .system(.rectangleSplit2x2),
                helpText: "Toggle workspace management mode",
                surfacePolicy: .exposed([.commandBar, .toolbar(.app)]),
                targeting: .contextual
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
            return managementDefinition(
                shortcut: .managementLayerEnterDrawer,
                label: "Management Enter Drawer",
                icon: .system(.arrowDown),
                helpText: "Enter or expand the current drawer in management mode"
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
            return windowDefinition(
                shortcut: .toggleSidebar,
                label: "Toggle Sidebar",
                icon: .system(.sidebarLeft),
                helpText: "Show or hide the sidebar",
                surfacePolicy: .exposed([.commandBar]),
                targeting: .contextual
            )
        case .showInboxNotifications:
            return windowDefinition(
                shortcut: .showInboxNotifications,
                label: "Toggle Inbox",
                icon: .system(.bell),
                helpText: "Show or hide the notification inbox in the sidebar",
                surfacePolicy: .exposed([.commandBar, .toolbar(.app)]),
                targeting: .contextual
            )
        case .toggleInboxNotificationSort:
            return inboxActionDefinition(
                label: "Toggle Inbox Sort Order",
                icon: .system(.arrowUpArrowDown),
                helpText: "Switch the inbox between newest-first and oldest-first order"
            )
        case .clearReadInboxNotifications:
            return inboxActionDefinition(
                label: "Clear Read Inbox Notifications",
                icon: .system(.deleteLeft),
                helpText: "Remove read notifications from the inbox history"
            )
        case .clearAllInboxNotifications:
            return inboxActionDefinition(
                label: "Clear All Inbox Notifications",
                icon: .system(.deleteLeft),
                helpText: "Remove every notification from the inbox history"
            )
        case .showPaneInboxNotifications:
            return paneInboxDefinition(
                shortcut: .showPaneInboxNotifications,
                label: "Toggle Pane Inbox",
                icon: .system(.bellBadge),
                helpText: "Show notifications for the active pane and its drawer children",
                surfacePolicy: .exposed([.commandBar, .toolbar(.pane), .toolbar(.terminalZoom)])
            )
        case .clearPaneInboxNotifications:
            return paneInboxDefinition(
                label: "Clear Pane Inbox",
                icon: .system(.deleteLeft),
                helpText: "Clear notifications for the active pane and its drawer children",
                surfacePolicy: .exposed([.commandBar, .inlineControl])
            )
        case .showWorktreeSidebar:
            return windowDefinition(
                shortcut: .showWorktreeSidebar,
                label: "Toggle Worktrees",
                icon: .system(.sidebarLeft),
                helpText: "Show or hide the repo explorer in the sidebar",
                surfacePolicy: .exposed([.commandBar, .toolbar(.app)]),
                targeting: .contextual
            )
        case .setRepoSidebarGroupingRepo:
            return repoSidebarGroupingDefinition(
                label: "Repo",
                icon: .system(.folder),
                helpTarget: "repo"
            )
        case .setRepoSidebarGroupingPane:
            return repoSidebarGroupingDefinition(
                label: "Pane",
                icon: .system(.rectangleSplit2x1),
                helpTarget: "pane"
            )
        case .setRepoSidebarGroupingTab:
            return repoSidebarGroupingDefinition(
                label: "Tab",
                icon: .system(.rectangleStack),
                helpTarget: "tab"
            )
        case .setRepoSidebarVisibilityMode:
            return repoSidebarVisibilityDefinition()
        case .setRepoSidebarSortOrder:
            return repoSidebarSortOrderDefinition()
        case .setInboxGroupingTab:
            return inboxGroupingDefinition(
                label: "Tab",
                icon: .system(.rectangleStack),
                helpTarget: "tab"
            )
        case .setInboxGroupingRepo:
            return inboxGroupingDefinition(
                label: "Repo",
                icon: .system(.folder),
                helpTarget: "repo"
            )
        case .setInboxGroupingPane:
            return inboxGroupingDefinition(
                label: "Pane",
                icon: .system(.rectangleSplit2x1),
                helpTarget: "pane"
            )
        case .setInboxGroupingNone:
            return inboxGroupingDefinition(
                label: "None",
                icon: .system(.line3Horizontal),
                helpTarget: "a flat list"
            )
        case .setInboxRowStateFilter:
            return inboxRowStateFilterDefinition()
        case .setInboxContentMode:
            return inboxContentModeDefinition()
        case .newFloatingTerminal:
            return windowDefinition(
                label: "New Floating Terminal",
                icon: .system(.terminalFill),
                helpText: "Open a new floating terminal",
                surfacePolicy: .exposed([.commandBar, .contextMenu]),
                targeting: .contextualAndTargeted(
                    [.tab],
                    preferredInvocation: .contextual
                )
            )
        case .newWindow:
            return windowDefinition(
                shortcut: .newWindow,
                label: "New Window",
                icon: .system(.macwindowBadgePlus),
                helpText: "Open a new application window",
                surfacePolicy: .exposed([.mainMenu]),
                targeting: .contextual
            )
        case .closeWindow:
            return windowDefinition(
                shortcut: .closeWindow,
                label: "Close Window",
                icon: .system(.xmarkRectangle),
                helpText: "Close the current application window",
                surfacePolicy: .exposed([.mainMenu]),
                targeting: .contextual
            )
        case .showCommandBarEverything:
            return commandBarNavigationDefinition(
                shortcut: .showCommandBarEverything,
                label: "Quick Find",
                icon: .system(.magnifyingglass),
                helpText: "Open quick find",
                surfacePolicy: .exposed([.commandBar, .mainMenu, .inlineControl])
            )
        case .showCommandBarQuickOpen:
            return commandBarNavigationDefinition(
                shortcut: .newTab,
                label: "Quick Open",
                icon: .system(.terminal),
                helpText: "Open a terminal at a repository or worktree",
                surfacePolicy: .exposed([.commandBar])
            )
        case .showCommandBarCommands:
            return commandBarNavigationDefinition(
                shortcut: .showCommandBarCommands,
                label: "Command Palette",
                icon: .system(.command),
                helpText: "Open the command palette",
                surfacePolicy: .exposed([.commandBar, .mainMenu])
            )
        case .showCommandBarPanes:
            return commandBarNavigationDefinition(
                shortcut: .showCommandBarPanes,
                label: "Go to Pane",
                icon: .system(.terminal),
                helpText: "Open the pane picker",
                surfacePolicy: .exposed([.commandBar, .mainMenu])
            )
        case .showCommandBarRepos:
            return commandBarNavigationDefinition(
                label: "Repositories",
                icon: .system(.folder),
                helpText: "Open the repository navigator",
                surfacePolicy: .exposed([.commandBar, .mainMenu, .contextMenu, .inlineControl])
            )
        case .openWebview:
            return openWebviewDefinition()
        case .reloadBridgeWebView:
            return bridgeWebViewReloadDefinition()
        case .showViewer:
            return AppCommandSpec(
                command: self,
                shortcut: .showViewer,
                label: "Worktree Viewer",
                icon: .system(.textPageBadgeMagnifyingglass),
                helpText: "Show or hide the Worktree Viewer in Pane Zoom",
                surfacePolicy: .exposed([.commandBar, .toolbar(.terminalZoom)]),
                targeting: .contextualAndTargeted([.pane], preferredInvocation: .contextual),
                visibleWhen: [.supportsTerminalZoom],
                commandBarGroupName: "Worktree Viewer",
                commandBarGroupPriority: CommandBarGroupPriority.worktreeViewer
            )
        case .showBridgeReview:
            return bridgeDefinition(
                label: "Review",
                icon: .system(.rectangleSplit2x1),
                helpText: "Open the read-only review in a tab"
            )
        case .showBridgeFiles:
            return bridgeDefinition(
                label: "Files",
                icon: .system(.folder),
                helpText: "Open the worktree file viewer in a tab"
            )
        case .openBridgeReviewInNewTab:
            return bridgeDefinition(
                label: "Open Review in New Tab",
                icon: .system(.rectangleSplit2x1),
                helpText: "Open an independent read-only review in a new tab"
            )
        case .openBridgeFilesInNewTab:
            return bridgeDefinition(
                label: "Open Files in New Tab",
                icon: .system(.folder),
                helpText: "Open an independent worktree file viewer in a new tab"
            )
        case .signInGitHub:
            return authenticationDefinition(providerName: "GitHub")
        case .signInGoogle:
            return authenticationDefinition(providerName: "Google")
        case .filterSidebar:
            return windowDefinition(
                shortcut: .filterSidebar,
                label: "Filter Sidebar",
                icon: .system(.magnifyingglass),
                helpText: "Filter items in the sidebar",
                surfacePolicy: .exposed([.commandBar, .mainMenu]),
                targeting: .contextual
            )
        case .openNewTerminalInTab:
            return worktreeDefinition(
                label: "Open Terminal in New Tab",
                icon: .system(.terminalFill),
                helpText: "Open a worktree in a fresh terminal tab",
                surfacePolicy: .exposed([.commandBar, .contextMenu])
            )
        }
    }
}
