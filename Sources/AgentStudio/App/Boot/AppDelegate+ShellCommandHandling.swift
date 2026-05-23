import Foundation

extension AppDelegate: ShellCommandHandling {
    func canExecute(_ command: AppCommand) -> Bool {
        switch command {
        case .watchFolder, .toggleSidebar, .filterSidebar,
            .showInboxNotifications, .toggleInboxNotificationSort,
            .clearReadInboxNotifications, .clearAllInboxNotifications, .showWorktreeSidebar,
            .signInGitHub, .signInGoogle, .newWindow, .closeWindow,
            .showCommandBarEverything, .showCommandBarCommands, .showCommandBarPanes, .showCommandBarRepos:
            true
        case .closeTab, .breakUpTab, .renameTab, .newTerminalInTab, .newTab, .undoCloseTab,
            .selectTab, .nextTab, .prevTab,
            .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9,
            .closePane, .extractPaneToTab, .movePaneToTab, .focusPane, .scrollToBottom,
            .splitRight, .splitLeft, .equalizePanes,
            .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown,
            .focusNextPane, .focusPrevPane, .toggleSplitZoom, .minimizePane, .expandPane,
            .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
            .focusPane6, .focusPane7, .focusPane8, .focusPane9,
            .switchArrangement, .cycleArrangement, .saveArrangement, .deleteArrangement, .renameArrangement,
            .enterDrawer, .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown,
            .focusDrawerPaneRight,
            .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
            .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
            .focusDrawerPane9,
            .detachDrawerPane, .addDrawerPane, .toggleDrawer,
            .navigateDrawerPane, .closeDrawerPane,
            .openPaneLocationInBookmarkedEditor, .openPaneLocationInFinder, .openPaneLocationInEditorMenu,
            .removeRepo, .openWorktree, .openWorktreeInPane,
            .toggleManagementLayer,
            .managementLayerFocusLeft, .managementLayerFocusRight,
            .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal, .managementLayerCreateBrowser,
            .managementLayerExit,
            .showPaneInboxNotifications, .clearPaneInboxNotifications,
            .newFloatingTerminal, .openWebview, .openNewTerminalInTab:
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
            .splitRight, .splitLeft, .equalizePanes,
            .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown,
            .focusNextPane, .focusPrevPane, .toggleSplitZoom, .minimizePane, .expandPane,
            .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
            .focusPane6, .focusPane7, .focusPane8, .focusPane9,
            .switchArrangement, .cycleArrangement, .saveArrangement, .deleteArrangement, .renameArrangement,
            .enterDrawer, .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown,
            .focusDrawerPaneRight,
            .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
            .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
            .focusDrawerPane9,
            .detachDrawerPane, .addDrawerPane, .toggleDrawer,
            .navigateDrawerPane, .closeDrawerPane,
            .openPaneLocationInBookmarkedEditor, .openPaneLocationInFinder, .openPaneLocationInEditorMenu,
            .removeRepo, .openWorktree, .openWorktreeInPane,
            .toggleManagementLayer,
            .managementLayerFocusLeft, .managementLayerFocusRight,
            .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal, .managementLayerCreateBrowser,
            .managementLayerExit,
            .showPaneInboxNotifications, .clearPaneInboxNotifications,
            .newFloatingTerminal, .openWebview, .openNewTerminalInTab:
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
            .splitRight, .splitLeft, .equalizePanes,
            .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown,
            .focusNextPane, .focusPrevPane, .toggleSplitZoom, .minimizePane, .expandPane,
            .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
            .focusPane6, .focusPane7, .focusPane8, .focusPane9,
            .switchArrangement, .cycleArrangement, .saveArrangement, .deleteArrangement, .renameArrangement,
            .enterDrawer, .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown,
            .focusDrawerPaneRight,
            .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
            .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
            .focusDrawerPane9,
            .detachDrawerPane, .addDrawerPane, .toggleDrawer,
            .navigateDrawerPane, .closeDrawerPane,
            .openPaneLocationInBookmarkedEditor, .openPaneLocationInFinder, .openPaneLocationInEditorMenu,
            .watchFolder, .removeRepo, .openWorktree, .openWorktreeInPane,
            .toggleManagementLayer,
            .managementLayerFocusLeft, .managementLayerFocusRight,
            .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal, .managementLayerCreateBrowser,
            .managementLayerExit,
            .toggleSidebar, .showInboxNotifications, .toggleInboxNotificationSort,
            .clearReadInboxNotifications, .clearAllInboxNotifications,
            .showPaneInboxNotifications, .clearPaneInboxNotifications, .showWorktreeSidebar,
            .newFloatingTerminal, .newWindow, .closeWindow,
            .showCommandBarEverything, .showCommandBarCommands, .showCommandBarPanes, .showCommandBarRepos,
            .openWebview, .signInGitHub, .signInGoogle,
            .filterSidebar, .openNewTerminalInTab:
            return false
        }
    }
}
