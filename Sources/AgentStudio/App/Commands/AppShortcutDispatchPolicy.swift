import Foundation

@MainActor
enum AppShortcutDispatchPolicy {
    static func shouldRouteAppOwnedKeyEvent(context: KeyboardRoutingContext) -> Bool {
        switch context.activeSurface {
        case .commandBar, .transient:
            return false
        case .stable:
            return true
        }
    }

    static func shouldDispatchGlobalShortcut(
        _ shortcut: AppShortcut,
        context: KeyboardRoutingContext
    ) -> Bool {
        if isCommandBarActivationShortcut(shortcut) {
            return context.stableOwner != .otherWindow
        }

        return shouldDispatchFromActiveSurface(shortcut, context: context)
    }

    static func shouldConsumeUnavailableGlobalShortcut(
        _ shortcut: AppShortcut,
        context: KeyboardRoutingContext
    ) -> Bool {
        switch context.activeSurface {
        case .transient(.arrangementPanel):
            return shouldDispatchFromArrangementPanel(shortcut)
        case .commandBar, .stable, .transient:
            return false
        }
    }

    static func shouldDispatchTerminalAppOwnedShortcut(
        _ shortcut: AppShortcut,
        context: KeyboardRoutingContext
    ) -> Bool {
        if isCommandBarActivationShortcut(shortcut) {
            return context.stableOwner != .otherWindow
        }

        guard shouldDispatchTerminalAppOwnedShortcutFromActiveSurface(shortcut, context: context) else {
            return false
        }

        switch context.stableOwner {
        case .mainWindowChain, .managementLayer:
            return shortcut.spec.contexts.contains(.terminalAppOwned)
        case .sidebar, .otherWindow:
            return false
        }
    }

    static func sourcePaneTarget(for command: AppCommand, sourcePaneId: UUID?) -> UUID? {
        guard let sourcePaneId else { return nil }
        guard isTerminalRuntimeCommand(command) else { return nil }
        return sourcePaneId
    }

    static func shouldSuppressTerminalHostTrigger(_ trigger: ShortcutTrigger) -> Bool {
        trigger == ShortcutTrigger(key: .character(.k), modifiers: [.command])
    }

    static func isTerminalRuntimeCommand(_ command: AppCommand) -> Bool {
        switch command {
        case .scrollToBottom, .scrollPageUp, .jumpToPreviousPrompt, .jumpToNextPrompt:
            return true
        case .closeTab, .breakUpTab, .renameTab, .newTerminalInTab, .newTab, .undoCloseTab,
            .selectTab, .nextTab, .prevTab, .selectTab1, .selectTab2, .selectTab3,
            .selectTab4, .selectTab5, .selectTab6, .selectTab7, .selectTab8, .selectTab9,
            .closePane, .extractPaneToTab, .movePaneToTab, .focusPane, .splitRight, .splitLeft,
            .equalizePanes, .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown,
            .focusNextPane, .focusPrevPane, .focusPane1, .focusPane2, .focusPane3, .focusPane4,
            .focusPane5, .focusPane6, .focusPane7, .focusPane8, .focusPane9, .toggleSplitZoom,
            .minimizePane, .expandPane, .switchArrangement, .previousArrangement, .nextArrangement,
            .cycleArrangement, .saveArrangement, .deleteArrangement, .renameArrangement,
            .enterDrawer, .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown,
            .focusDrawerPaneRight, .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3,
            .focusDrawerPane4, .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7,
            .focusDrawerPane8, .focusDrawerPane9, .detachDrawerPane, .addDrawerPane,
            .toggleDrawer, .navigateDrawerPane, .closeDrawerPane,
            .openPaneLocationInBookmarkedEditor, .openPaneLocationInFinder,
            .openPaneLocationInEditorMenu, .watchFolder, .removeRepo, .openWorktree,
            .openWorktreeInPane, .toggleManagementLayer, .managementLayerFocusLeft,
            .managementLayerFocusRight, .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal,
            .managementLayerCreateBrowser, .managementLayerExit, .toggleSidebar,
            .showInboxNotifications, .toggleInboxNotificationSort, .clearReadInboxNotifications,
            .clearAllInboxNotifications, .showPaneInboxNotifications, .clearPaneInboxNotifications,
            .showWorktreeSidebar, .newFloatingTerminal, .newWindow, .closeWindow,
            .showCommandBarEverything, .showCommandBarCommands, .showCommandBarPanes,
            .showCommandBarRepos, .openWebview, .signInGitHub, .signInGoogle,
            .filterSidebar, .openNewTerminalInTab:
            return false
        }
    }

    static func isCommandBarActivationShortcut(_ shortcut: AppShortcut) -> Bool {
        switch shortcut {
        case .newTab, .showCommandBarEverything, .showCommandBarCommands, .showCommandBarPanes:
            return true
        case .closeTab, .undoCloseTab, .nextTab, .prevTab, .showArrangementPanel,
            .previousArrangement, .nextArrangement, .addDrawerPane, .toggleDrawer, .scrollToBottom,
            .scrollPageUp, .jumpToPreviousPrompt, .jumpToNextPrompt, .openPaneLocationInBookmarkedEditor,
            .openPaneLocationInFinder, .openPaneLocationInEditorMenu, .toggleManagementLayer,
            .toggleSidebar, .filterSidebar, .showInboxNotifications, .showPaneInboxNotifications,
            .showWorktreeSidebar, .newWindow, .closeWindow, .selectTab1, .selectTab2, .selectTab3,
            .selectTab4, .selectTab5, .selectTab6, .selectTab7, .selectTab8, .selectTab9,
            .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5, .focusPane6,
            .focusPane7, .focusPane8, .focusPane9, .managementLayerFocusLeft,
            .managementLayerFocusRight, .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal, .managementLayerCreateBrowser,
            .managementLayerExit:
            return false
        }
    }

    static func shouldDispatchGlobalShortcut(
        _ shortcut: AppShortcut,
        keyboardOwner: KeyboardOwner
    ) -> Bool {
        switch keyboardOwner {
        case .otherWindow:
            return false
        case .managementLayer, .mainWindowChain:
            return shouldDispatchFromMainWindowChain(shortcut)
        case .sidebar(let surface):
            return shouldDispatchFromSidebar(shortcut, surface: surface)
        }
    }

    private static func shouldDispatchFromActiveSurface(
        _ shortcut: AppShortcut,
        context: KeyboardRoutingContext
    ) -> Bool {
        switch context.activeSurface {
        case .commandBar:
            return false
        case .transient(let surface):
            guard shouldDispatchFromTransientSurface(shortcut, surface: surface) else {
                return false
            }
            return shouldDispatchGlobalShortcut(shortcut, keyboardOwner: context.stableOwner)
        case .stable:
            return shouldDispatchGlobalShortcut(shortcut, keyboardOwner: context.stableOwner)
        }
    }

    private static func shouldDispatchTerminalAppOwnedShortcutFromActiveSurface(
        _ shortcut: AppShortcut,
        context: KeyboardRoutingContext
    ) -> Bool {
        switch context.activeSurface {
        case .commandBar:
            return false
        case .transient(let surface):
            return shouldDispatchFromTransientSurface(shortcut, surface: surface)
        case .stable:
            return true
        }
    }

    private static func shouldDispatchFromTransientSurface(
        _ shortcut: AppShortcut,
        surface: TransientKeyboardSurfaceKind
    ) -> Bool {
        switch surface {
        case .arrangementPanel:
            return shouldDispatchFromArrangementPanel(shortcut)
        case .tabRename, .arrangementRename, .paneInbox, .editorChooser:
            return false
        }
    }

    private static func shouldDispatchFromArrangementPanel(_ shortcut: AppShortcut) -> Bool {
        switch shortcut {
        case .previousArrangement, .nextArrangement, .prevTab, .nextTab,
            .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9:
            return true
        case .closeTab, .undoCloseTab, .newTab, .showArrangementPanel, .addDrawerPane,
            .toggleDrawer, .scrollToBottom, .scrollPageUp, .jumpToPreviousPrompt, .jumpToNextPrompt,
            .openPaneLocationInBookmarkedEditor, .openPaneLocationInFinder,
            .openPaneLocationInEditorMenu, .toggleManagementLayer, .toggleSidebar,
            .filterSidebar, .showInboxNotifications, .showPaneInboxNotifications,
            .showWorktreeSidebar, .showCommandBarEverything, .showCommandBarCommands,
            .showCommandBarPanes, .newWindow, .closeWindow, .focusPane1, .focusPane2,
            .focusPane3, .focusPane4, .focusPane5, .focusPane6, .focusPane7, .focusPane8,
            .focusPane9, .managementLayerFocusLeft, .managementLayerFocusRight,
            .managementLayerEnterDrawer, .managementLayerExitDrawer, .managementLayerOpenDrawer,
            .managementLayerCreateTerminal, .managementLayerCreateBrowser, .managementLayerExit:
            return false
        }
    }

    private static func shouldDispatchFromMainWindowChain(_ shortcut: AppShortcut) -> Bool {
        switch shortcut {
        case .filterSidebar, .scrollToBottom, .scrollPageUp, .jumpToPreviousPrompt, .jumpToNextPrompt:
            return false
        case .toggleSidebar, .closeTab, .newTab, .undoCloseTab, .nextTab, .prevTab,
            .showArrangementPanel, .previousArrangement, .nextArrangement,
            .addDrawerPane, .toggleDrawer, .openPaneLocationInBookmarkedEditor,
            .openPaneLocationInFinder, .openPaneLocationInEditorMenu, .toggleManagementLayer,
            .showInboxNotifications, .showPaneInboxNotifications, .showWorktreeSidebar,
            .newWindow, .closeWindow, .showCommandBarEverything, .showCommandBarCommands,
            .showCommandBarPanes, .selectTab1, .selectTab2, .selectTab3, .selectTab4,
            .selectTab5, .selectTab6, .selectTab7, .selectTab8, .selectTab9,
            .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5, .focusPane6,
            .focusPane7, .focusPane8, .focusPane9, .managementLayerFocusLeft,
            .managementLayerFocusRight, .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal, .managementLayerCreateBrowser,
            .managementLayerExit:
            return true
        }
    }

    private static func shouldDispatchFromSidebar(
        _ shortcut: AppShortcut,
        surface: SidebarSurface
    ) -> Bool {
        switch shortcut {
        case .filterSidebar:
            return surface == .repos
        case .toggleSidebar, .showInboxNotifications, .showWorktreeSidebar,
            .showCommandBarEverything, .showCommandBarCommands, .showCommandBarPanes:
            return true
        case .closeTab, .newTab, .undoCloseTab, .nextTab, .prevTab, .showArrangementPanel,
            .previousArrangement, .nextArrangement, .addDrawerPane, .toggleDrawer, .scrollToBottom,
            .scrollPageUp, .jumpToPreviousPrompt, .jumpToNextPrompt, .openPaneLocationInBookmarkedEditor,
            .openPaneLocationInFinder, .openPaneLocationInEditorMenu, .toggleManagementLayer,
            .showPaneInboxNotifications, .newWindow, .closeWindow, .selectTab1, .selectTab2,
            .selectTab3, .selectTab4, .selectTab5, .selectTab6, .selectTab7, .selectTab8,
            .selectTab9, .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
            .focusPane6, .focusPane7, .focusPane8, .focusPane9, .managementLayerFocusLeft,
            .managementLayerFocusRight, .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal, .managementLayerCreateBrowser,
            .managementLayerExit:
            return false
        }
    }
}
