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

    static func appCommandOverride(
        for trigger: ShortcutTrigger,
        context: KeyboardRoutingContext
    ) -> AppCommand? {
        switch context.activeSurface {
        case .transient(.arrangementPanel):
            return arrangementPanelCommandOverride(for: trigger, context: context)
        case .commandBar, .stable, .transient:
            return nil
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
            .showWorktreeSidebar, .newWindow, .closeWindow, .focusPane1, .focusPane2, .focusPane3,
            .focusPane4, .focusPane5, .focusPane6, .focusPane7, .focusPane8, .focusPane9,
            .managementLayerFocusLeft, .managementLayerFocusRight, .managementLayerEnterDrawer,
            .managementLayerExitDrawer, .managementLayerOpenDrawer, .managementLayerCreateTerminal,
            .managementLayerCreateBrowser, .managementLayerExit:
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
        case .previousArrangement, .nextArrangement, .prevTab, .nextTab:
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

    private static func arrangementPanelCommandOverride(
        for trigger: ShortcutTrigger,
        context: KeyboardRoutingContext
    ) -> AppCommand? {
        guard
            context.workspaceWindowId != nil,
            context.stableOwner != .otherWindow,
            trigger.modifiers == [.command],
            case .character(let key) = trigger.key
        else {
            return nil
        }

        switch key {
        case .digit1:
            return .selectTab1
        case .digit2:
            return .selectTab2
        case .digit3:
            return .selectTab3
        case .digit4:
            return .selectTab4
        case .digit5:
            return .selectTab5
        case .digit6:
            return .selectTab6
        case .digit7:
            return .selectTab7
        case .digit8:
            return .selectTab8
        case .digit9:
            return .selectTab9
        case .a, .b, .comma, .d, .e, .f, .i, .j, .k, .l, .leftBracket, .m, .n, .o, .p, .r,
            .rightBracket, .s, .t, .u, .w:
            return nil
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
            .showCommandBarPanes, .focusPane1, .focusPane2, .focusPane3, .focusPane4,
            .focusPane5, .focusPane6, .focusPane7, .focusPane8, .focusPane9,
            .managementLayerFocusLeft, .managementLayerFocusRight, .managementLayerEnterDrawer,
            .managementLayerExitDrawer, .managementLayerOpenDrawer, .managementLayerCreateTerminal,
            .managementLayerCreateBrowser, .managementLayerExit:
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
            .showPaneInboxNotifications, .newWindow, .closeWindow, .focusPane1, .focusPane2,
            .focusPane3, .focusPane4, .focusPane5, .focusPane6, .focusPane7, .focusPane8,
            .focusPane9, .managementLayerFocusLeft, .managementLayerFocusRight,
            .managementLayerEnterDrawer, .managementLayerExitDrawer, .managementLayerOpenDrawer,
            .managementLayerCreateTerminal, .managementLayerCreateBrowser, .managementLayerExit:
            return false
        }
    }
}
