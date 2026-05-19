import Foundation

@MainActor
enum AppShortcutDispatchPolicy {
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

    private static func shouldDispatchFromMainWindowChain(_ shortcut: AppShortcut) -> Bool {
        switch shortcut {
        case .filterSidebar, .scrollToBottom:
            return false
        case .toggleSidebar, .closeTab, .newTab, .undoCloseTab, .nextTab, .prevTab, .cycleArrangement,
            .addDrawerPane, .toggleDrawer, .openPaneLocationInBookmarkedEditor,
            .openPaneLocationInFinder, .openPaneLocationInEditorMenu, .toggleManagementLayer,
            .showInboxNotifications, .showPaneInboxNotifications, .showWorktreeSidebar,
            .newWindow, .closeWindow, .showCommandBarEverything, .showCommandBarCommands,
            .showCommandBarPanes, .selectTab1, .selectTab2, .selectTab3, .selectTab4,
            .selectTab5, .selectTab6, .selectTab7, .selectTab8, .selectTab9,
            .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
            .focusPane6, .focusPane7, .focusPane8, .focusPane9,
            .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
            .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
            .focusDrawerPane9,
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
        case .closeTab, .newTab, .undoCloseTab, .nextTab, .prevTab, .cycleArrangement, .addDrawerPane,
            .toggleDrawer, .scrollToBottom, .openPaneLocationInBookmarkedEditor,
            .openPaneLocationInFinder, .openPaneLocationInEditorMenu, .toggleManagementLayer,
            .showPaneInboxNotifications, .newWindow, .closeWindow, .selectTab1, .selectTab2,
            .selectTab3, .selectTab4, .selectTab5, .selectTab6, .selectTab7, .selectTab8,
            .selectTab9, .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
            .focusPane6, .focusPane7, .focusPane8, .focusPane9,
            .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
            .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
            .focusDrawerPane9, .managementLayerFocusLeft, .managementLayerFocusRight,
            .managementLayerEnterDrawer, .managementLayerExitDrawer, .managementLayerOpenDrawer,
            .managementLayerCreateTerminal, .managementLayerCreateBrowser, .managementLayerExit:
            return false
        }
    }
}
