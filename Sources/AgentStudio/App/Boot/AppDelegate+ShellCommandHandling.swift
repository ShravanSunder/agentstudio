import AgentStudioCore
import AgentStudioRepoExplorer
import Foundation

extension AppDelegate: ShellCommandHandling {
    func canExecute(_ request: AppCommandExecutionRequest) -> Bool {
        if request.arguments == .noArguments {
            return canExecute(request.command)
        }
        guard atomStore != nil else { return false }
        switch (request.command, request.arguments) {
        case (.setRepoSidebarSortOrder, .repoSidebarSortOrder):
            return true
        default:
            return false
        }
    }

    func canExecute(_ command: AppCommand) -> Bool {
        switch command {
        case .watchFolder, .toggleSidebar, .filterSidebar,
            .showWorktreeSidebar,
            .setRepoSidebarGroupingRepo, .setRepoSidebarGroupingPane, .setRepoSidebarGroupingTab,
            .signInGitHub, .signInGoogle, .newWindow, .closeWindow,
            .showCommandBarEverything, .showCommandBarQuickOpen, .showCommandBarCommands,
            .showCommandBarPanes, .showCommandBarRepos:
            true
        case .closeTab, .breakUpTab, .renameTab, .newTerminalInTab, .newTab, .undoCloseTab,
            .selectTab, .nextTab, .prevTab,
            .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9,
            .closePane, .extractPaneToTab, .movePaneToTab, .focusPane, .scrollToBottom,
            .scrollPageUp, .jumpToPreviousPrompt, .jumpToNextPrompt,
            .splitRight, .splitLeft, .equalizePanes,
            .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown,
            .focusNextPane, .focusPrevPane, .zoomPane, .minimizePane, .expandPane,
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
            .editPaneNote, .copyCurrentPanePath, .openPullRequest,
            .removeRepo, .addRepoFavorite, .removeRepoFavorite, .openWorktree, .openWorktreeInPane,
            .toggleManagementLayer,
            .managementLayerFocusLeft, .managementLayerFocusRight,
            .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal, .managementLayerCreateBrowser,
            .managementLayerExit,
            .showInboxNotifications, .toggleInboxNotificationSort,
            .clearReadInboxNotifications, .clearAllInboxNotifications,
            .showPaneInboxNotifications, .clearPaneInboxNotifications,
            .setInboxGroupingTab, .setInboxGroupingRepo, .setInboxGroupingPane,
            .setInboxGroupingNone,
            .newFloatingTerminal, .openWebview, .reloadBridgeWebView, .showViewer,
            .showBridgeReview, .showBridgeFiles,
            .setRepoSidebarSortOrder,
            .setInboxRowStateFilter, .setInboxContentMode,
            .openBridgeReviewInNewTab, .openBridgeFilesInNewTab, .openNewTerminalInTab:
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
            return false
        case .toggleInboxNotificationSort:
            return false
        case .clearReadInboxNotifications:
            return false
        case .clearAllInboxNotifications:
            return false
        case .showWorktreeSidebar:
            mainWindowController?.showWorktreeSidebar()
            return true
        case .setRepoSidebarGroupingRepo, .setRepoSidebarGroupingPane, .setRepoSidebarGroupingTab:
            return executeSidebarGroupingCommand(command) == .applied
        case .setRepoSidebarSortOrder:
            return false
        case .setInboxRowStateFilter, .setInboxContentMode:
            return false
        case .setInboxGroupingTab, .setInboxGroupingRepo, .setInboxGroupingPane,
            .setInboxGroupingNone:
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
        case .showCommandBarQuickOpen:
            showCommandBar(defaultRootScope: .quickOpen, context: "command bar (quick open)")
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
            .focusNextPane, .focusPrevPane, .zoomPane, .minimizePane, .expandPane,
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
            .editPaneNote, .copyCurrentPanePath, .openPullRequest,
            .removeRepo, .addRepoFavorite, .removeRepoFavorite, .openWorktree, .openWorktreeInPane,
            .toggleManagementLayer,
            .managementLayerFocusLeft, .managementLayerFocusRight,
            .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal, .managementLayerCreateBrowser,
            .managementLayerExit,
            .showPaneInboxNotifications, .clearPaneInboxNotifications,
            .newFloatingTerminal, .openWebview, .reloadBridgeWebView, .showViewer,
            .showBridgeReview, .showBridgeFiles,
            .openBridgeReviewInNewTab, .openBridgeFilesInNewTab, .openNewTerminalInTab:
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
            .focusNextPane, .focusPrevPane, .zoomPane, .minimizePane, .expandPane,
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
            .editPaneNote, .copyCurrentPanePath, .openPullRequest,
            .watchFolder, .removeRepo, .addRepoFavorite, .removeRepoFavorite,
            .openWorktree, .openWorktreeInPane,
            .toggleManagementLayer,
            .managementLayerFocusLeft, .managementLayerFocusRight,
            .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal, .managementLayerCreateBrowser,
            .managementLayerExit,
            .toggleSidebar, .showInboxNotifications, .toggleInboxNotificationSort,
            .clearReadInboxNotifications, .clearAllInboxNotifications,
            .showPaneInboxNotifications, .clearPaneInboxNotifications, .showWorktreeSidebar,
            .setRepoSidebarGroupingRepo, .setRepoSidebarGroupingPane, .setRepoSidebarGroupingTab,
            .setRepoSidebarSortOrder,
            .setInboxGroupingTab, .setInboxGroupingRepo, .setInboxGroupingPane, .setInboxGroupingNone,
            .setInboxRowStateFilter, .setInboxContentMode,
            .newFloatingTerminal, .newWindow, .closeWindow,
            .showCommandBarEverything, .showCommandBarQuickOpen, .showCommandBarCommands,
            .showCommandBarPanes, .showCommandBarRepos,
            .openWebview, .reloadBridgeWebView, .showViewer, .showBridgeReview, .showBridgeFiles,
            .openBridgeReviewInNewTab, .openBridgeFilesInNewTab, .signInGitHub, .signInGoogle,
            .filterSidebar, .openNewTerminalInTab:
            return false
        }
    }

    func execute(_ request: AppCommandExecutionRequest) -> AppCommandExecutionOutcome {
        switch (request.command, request.arguments) {
        case (.showWorktreeSidebar, .noArguments) where request.executionContext == .headlessIPC:
            return executeHeadlessRepoSidebarCommand()
        case (.setRepoSidebarSortOrder, .repoSidebarSortOrder(let order)):
            return executeRepoSidebarSortOrderCommand(order)
        case (.setRepoSidebarGroupingRepo, .noArguments), (.setRepoSidebarGroupingPane, .noArguments),
            (.setRepoSidebarGroupingTab, .noArguments):
            return executeSidebarGroupingCommand(request.command)
        case (.showInboxNotifications, _), (.toggleInboxNotificationSort, _),
            (.clearReadInboxNotifications, _), (.clearAllInboxNotifications, _),
            (.showPaneInboxNotifications, _), (.clearPaneInboxNotifications, _),
            (.setInboxGroupingTab, _), (.setInboxGroupingRepo, _),
            (.setInboxGroupingPane, _), (.setInboxGroupingNone, _),
            (.setInboxRowStateFilter, _), (.setInboxContentMode, _):
            return .unsupportedCommand
        default:
            return execute(request.command) ? .applied : .unsupportedCommand
        }
    }

    private func executeSidebarGroupingCommand(_ command: AppCommand) -> AppCommandExecutionOutcome {
        guard let atomStore else { return .stateUnavailable }
        switch command {
        case .setRepoSidebarGroupingRepo:
            atomStore.repoExplorerSidebarPrefs.setGroupingMode(.repo)
            return atomStore.repoExplorerSidebarPrefs.groupingMode == .repo ? .applied : .stateUnavailable
        case .setRepoSidebarGroupingPane:
            atomStore.repoExplorerSidebarPrefs.setGroupingMode(.pane)
            return atomStore.repoExplorerSidebarPrefs.groupingMode == .pane ? .applied : .stateUnavailable
        case .setRepoSidebarGroupingTab:
            atomStore.repoExplorerSidebarPrefs.setGroupingMode(.tab)
            return atomStore.repoExplorerSidebarPrefs.groupingMode == .tab ? .applied : .stateUnavailable
        default:
            return .unsupportedCommand
        }
    }

    private func executeHeadlessRepoSidebarCommand() -> AppCommandExecutionOutcome {
        guard let atomStore else { return .stateUnavailable }
        atomStore.core.workspaceSidebarState.setSidebarSurface(.repos)
        mainWindowController?.expandSidebar()
        guard
            atomStore.core.workspaceSidebarState.sidebarSurface == .repos,
            atomStore.core.workspaceSidebarState.sidebarCollapsed == false
        else {
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
