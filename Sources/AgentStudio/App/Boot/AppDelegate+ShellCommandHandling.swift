import Foundation

extension AppDelegate: ShellCommandHandling {
    func canExecute(_ command: AppCommand) -> Bool {
        switch command {
        case .watchFolder, .toggleSidebar, .filterSidebar,
            .showInboxNotifications, .toggleInboxNotificationSort,
            .clearReadInboxNotifications, .clearAllInboxNotifications, .showWorktreeSidebar,
            .setRepoSidebarGroupingRepo, .setRepoSidebarGroupingPane, .setRepoSidebarGroupingTab,
            .setRepoSidebarVisibilityMode, .setRepoSidebarSortOrder,
            .setInboxGroupingTab, .setInboxGroupingRepo, .setInboxGroupingPane, .setInboxGroupingNone,
            .signInGitHub, .signInGoogle, .newWindow, .closeWindow,
            .showCommandBarEverything, .showCommandBarCommands, .showCommandBarPanes, .showCommandBarRepos:
            true
        case .closeTab, .breakUpTab, .renameTab, .newTerminalInTab, .newTab, .undoCloseTab,
            .selectTab, .nextTab, .prevTab,
            .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9,
            .closePane, .extractPaneToTab, .movePaneToTab, .focusPane, .scrollToBottom,
            .scrollPageUp, .jumpToPreviousPrompt, .jumpToNextPrompt,
            .splitRight, .splitLeft, .equalizePanes,
            .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown,
            .focusNextPane, .focusPrevPane, .toggleSplitZoom, .minimizePane, .expandPane,
            .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
            .focusPane6, .focusPane7, .focusPane8, .focusPane9,
            .switchArrangement, .previousArrangement, .nextArrangement, .cycleArrangement,
            .saveArrangement, .deleteArrangement, .renameArrangement,
            .enterDrawer, .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown,
            .focusDrawerPaneRight,
            .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
            .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
            .focusDrawerPane9,
            .detachDrawerPane, .addDrawerPane, .toggleDrawer,
            .navigateDrawerPane, .closeDrawerPane,
            .openPaneLocationInBookmarkedEditor, .openPaneLocationInFinder, .openPaneLocationInEditorMenu,
            .editPaneNote, .copyCurrentPanePath,
            .removeRepo, .openWorktree, .openWorktreeInPane,
            .toggleManagementLayer,
            .managementLayerFocusLeft, .managementLayerFocusRight,
            .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal, .managementLayerCreateBrowser,
            .managementLayerExit,
            .showPaneInboxNotifications, .clearPaneInboxNotifications,
            .newFloatingTerminal, .openWebview, .openBridgeReview, .openNewTerminalInTab:
            false
        }
    }

    func execute(_ command: AppCommand) -> Bool {
        switch command {
        case .watchFolder:
            Task { await handleWatchFolderRequested() }
            return true
        case .toggleSidebar:
            mainWindowController?.toggleSidebar()
            return true
        case .filterSidebar:
            mainWindowController?.showSidebarFilter()
            return true
        case .showInboxNotifications:
            mainWindowController?.showInboxNotifications(commandBarIsKey: commandBarController.isKeyWindow)
            return true
        case .toggleInboxNotificationSort:
            guard let atomStore else { return true }
            atomStore.inboxNotificationPrefs.setSort(
                atomStore.inboxNotificationPrefs.sort == .newestFirst ? .oldestFirst : .newestFirst
            )
            return true
        case .clearReadInboxNotifications:
            atomStore?.inboxNotification.clearReadHistory()
            return true
        case .clearAllInboxNotifications:
            atomStore?.inboxNotification.clearAll()
            return true
        case .showWorktreeSidebar:
            mainWindowController?.showWorktreeSidebar()
            return true
        case .setRepoSidebarGroupingRepo, .setRepoSidebarGroupingPane, .setRepoSidebarGroupingTab,
            .setInboxGroupingTab, .setInboxGroupingRepo, .setInboxGroupingPane, .setInboxGroupingNone:
            return executeSidebarGroupingCommand(command)
        case .setRepoSidebarVisibilityMode:
            return false
        case .setRepoSidebarSortOrder:
            return false
        case .newWindow:
            newWindow()
            return true
        case .closeWindow:
            closeWindow()
            return true
        case .showCommandBarEverything:
            showCommandBar(prefix: nil, context: "command bar")
            return true
        case .showCommandBarCommands:
            showCommandBar(prefix: ">", context: "command bar (commands)")
            return true
        case .showCommandBarPanes:
            showCommandBar(prefix: "$", context: "command bar (panes)")
            return true
        case .showCommandBarRepos:
            showCommandBar(prefix: "#", context: "command bar (repos)")
            return true
        case .signInGitHub:
            handleSignInRequested(provider: .github)
            return true
        case .signInGoogle:
            handleSignInRequested(provider: .google)
            return true
        case .closeTab, .breakUpTab, .renameTab, .newTerminalInTab, .newTab, .undoCloseTab,
            .selectTab, .nextTab, .prevTab,
            .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9,
            .closePane, .extractPaneToTab, .movePaneToTab, .focusPane, .scrollToBottom,
            .scrollPageUp, .jumpToPreviousPrompt, .jumpToNextPrompt,
            .splitRight, .splitLeft, .equalizePanes,
            .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown,
            .focusNextPane, .focusPrevPane, .toggleSplitZoom, .minimizePane, .expandPane,
            .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
            .focusPane6, .focusPane7, .focusPane8, .focusPane9,
            .switchArrangement, .previousArrangement, .nextArrangement, .cycleArrangement,
            .saveArrangement, .deleteArrangement, .renameArrangement,
            .enterDrawer, .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown,
            .focusDrawerPaneRight,
            .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
            .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
            .focusDrawerPane9,
            .detachDrawerPane, .addDrawerPane, .toggleDrawer,
            .navigateDrawerPane, .closeDrawerPane,
            .openPaneLocationInBookmarkedEditor, .openPaneLocationInFinder, .openPaneLocationInEditorMenu,
            .editPaneNote, .copyCurrentPanePath,
            .removeRepo, .openWorktree, .openWorktreeInPane,
            .toggleManagementLayer,
            .managementLayerFocusLeft, .managementLayerFocusRight,
            .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal, .managementLayerCreateBrowser,
            .managementLayerExit,
            .showPaneInboxNotifications, .clearPaneInboxNotifications,
            .newFloatingTerminal, .openWebview, .openBridgeReview, .openNewTerminalInTab:
            return false
        }
    }

    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool {
        _ = target
        _ = targetType
        switch command {
        case .closeTab, .breakUpTab, .renameTab, .newTerminalInTab, .newTab, .undoCloseTab,
            .selectTab, .nextTab, .prevTab,
            .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9,
            .closePane, .extractPaneToTab, .movePaneToTab, .focusPane, .scrollToBottom,
            .scrollPageUp, .jumpToPreviousPrompt, .jumpToNextPrompt,
            .splitRight, .splitLeft, .equalizePanes,
            .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown,
            .focusNextPane, .focusPrevPane, .toggleSplitZoom, .minimizePane, .expandPane,
            .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
            .focusPane6, .focusPane7, .focusPane8, .focusPane9,
            .switchArrangement, .previousArrangement, .nextArrangement, .cycleArrangement,
            .saveArrangement, .deleteArrangement, .renameArrangement,
            .enterDrawer, .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown,
            .focusDrawerPaneRight,
            .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
            .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
            .focusDrawerPane9,
            .detachDrawerPane, .addDrawerPane, .toggleDrawer,
            .navigateDrawerPane, .closeDrawerPane,
            .openPaneLocationInBookmarkedEditor, .openPaneLocationInFinder, .openPaneLocationInEditorMenu,
            .editPaneNote, .copyCurrentPanePath,
            .watchFolder, .removeRepo, .openWorktree, .openWorktreeInPane,
            .toggleManagementLayer,
            .managementLayerFocusLeft, .managementLayerFocusRight,
            .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal, .managementLayerCreateBrowser,
            .managementLayerExit,
            .toggleSidebar, .showInboxNotifications, .toggleInboxNotificationSort,
            .clearReadInboxNotifications, .clearAllInboxNotifications,
            .showPaneInboxNotifications, .clearPaneInboxNotifications, .showWorktreeSidebar,
            .setRepoSidebarGroupingRepo, .setRepoSidebarGroupingPane, .setRepoSidebarGroupingTab,
            .setRepoSidebarVisibilityMode, .setRepoSidebarSortOrder,
            .setInboxGroupingTab, .setInboxGroupingRepo, .setInboxGroupingPane, .setInboxGroupingNone,
            .newFloatingTerminal, .newWindow, .closeWindow,
            .showCommandBarEverything, .showCommandBarCommands, .showCommandBarPanes, .showCommandBarRepos,
            .openWebview, .openBridgeReview, .signInGitHub, .signInGoogle,
            .filterSidebar, .openNewTerminalInTab:
            return false
        }
    }

    func execute(_ request: AppCommandExecutionRequest) -> AppCommandExecutionOutcome {
        switch (request.command, request.arguments) {
        case (.showWorktreeSidebar, nil) where request.executionContext == .headlessIPC:
            return executeHeadlessRepoSidebarCommand()
        case (.showInboxNotifications, nil) where request.executionContext == .headlessIPC:
            return executeHeadlessInboxSidebarCommand()
        case (.setRepoSidebarVisibilityMode, .repoSidebarVisibilityMode(let mode)):
            return executeRepoSidebarVisibilityCommand(mode)
        case (.setRepoSidebarSortOrder, .repoSidebarSortOrder(let order)):
            return executeRepoSidebarSortOrderCommand(order)
        default:
            return execute(request.command) ? .applied : .unsupportedCommand
        }
    }

    private func executeSidebarGroupingCommand(_ command: AppCommand) -> Bool {
        switch command {
        case .setRepoSidebarGroupingRepo:
            atomStore?.repoExplorerSidebarPrefs.setGroupingMode(.repo)
        case .setRepoSidebarGroupingPane:
            atomStore?.repoExplorerSidebarPrefs.setGroupingMode(.pane)
        case .setRepoSidebarGroupingTab:
            atomStore?.repoExplorerSidebarPrefs.setGroupingMode(.tab)
        case .setInboxGroupingTab:
            atomStore?.inboxNotificationPrefs.setGrouping(.byTab)
        case .setInboxGroupingRepo:
            atomStore?.inboxNotificationPrefs.setGrouping(.byRepo)
        case .setInboxGroupingPane:
            atomStore?.inboxNotificationPrefs.setGrouping(.byPane)
        case .setInboxGroupingNone:
            atomStore?.inboxNotificationPrefs.setGrouping(.none)
        default:
            return false
        }
        return true
    }

    private func executeHeadlessRepoSidebarCommand() -> AppCommandExecutionOutcome {
        guard let atomStore else { return .stateUnavailable }
        atomStore.workspaceSidebarState.setSidebarSurface(.repos)
        mainWindowController?.expandSidebar()
        guard
            atomStore.workspaceSidebarState.sidebarSurface == .repos,
            atomStore.workspaceSidebarState.sidebarCollapsed == false
        else {
            return .stateUnavailable
        }
        return .applied
    }

    private func executeHeadlessInboxSidebarCommand() -> AppCommandExecutionOutcome {
        guard let atomStore else { return .stateUnavailable }
        atomStore.workspaceSidebarState.setSidebarSurface(.inbox)
        mainWindowController?.expandSidebar()
        guard
            atomStore.workspaceSidebarState.sidebarSurface == .inbox,
            atomStore.workspaceSidebarState.sidebarCollapsed == false
        else {
            return .stateUnavailable
        }
        return .applied
    }

    private func executeRepoSidebarVisibilityCommand(_ mode: RepoExplorerVisibilityMode) -> AppCommandExecutionOutcome {
        guard let atomStore else { return .stateUnavailable }
        atomStore.repoExplorerSidebarPrefs.setRepoVisibilityMode(mode)
        guard atomStore.repoExplorerSidebarPrefs.repoVisibilityMode == mode else {
            return .stateUnavailable
        }
        return .applied
    }

    private func executeRepoSidebarSortOrderCommand(_ order: RepoExplorerSortOrder) -> AppCommandExecutionOutcome {
        guard let atomStore else { return .stateUnavailable }
        atomStore.repoExplorerSidebarPrefs.setSortOrder(order)
        guard atomStore.repoExplorerSidebarPrefs.sortOrder == order else {
            return .stateUnavailable
        }
        return .applied
    }
}
