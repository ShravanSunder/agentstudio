import Foundation

// MARK: - AppCommand
/// All available commands in the application.
/// Every action — keyboard shortcut, menu item, context menu, command bar, search result,
/// or management layer click — is backed by a command.
enum AppCommand: String, CaseIterable {
    // Tab commands
    case closeTab
    case breakUpTab
    case renameTab
    case newTerminalInTab
    case newTab
    case undoCloseTab
    case selectTab
    case nextTab
    case prevTab
    case selectTab1, selectTab2, selectTab3, selectTab4, selectTab5
    case selectTab6, selectTab7, selectTab8, selectTab9
    // Pane commands
    case closePane
    case extractPaneToTab
    case movePaneToTab
    case focusPane
    case scrollToBottom
    case scrollPageUp
    case jumpToPreviousPrompt
    case jumpToNextPrompt
    case splitRight, splitLeft
    case equalizePanes
    case focusPaneLeft, focusPaneRight, focusPaneUp, focusPaneDown
    case focusNextPane, focusPrevPane
    case focusPane1, focusPane2, focusPane3, focusPane4, focusPane5
    case focusPane6, focusPane7, focusPane8, focusPane9
    case toggleSplitZoom
    case minimizePane
    case expandPane
    // Arrangement commands
    case switchArrangement
    case previousArrangement
    case nextArrangement
    case cycleArrangement
    case saveArrangement
    case deleteArrangement
    case renameArrangement
    // Drawer commands
    case enterDrawer
    case focusDrawerPaneUp
    case focusDrawerPaneLeft
    case focusDrawerPaneDown
    case focusDrawerPaneRight
    case focusDrawerPane1, focusDrawerPane2, focusDrawerPane3, focusDrawerPane4, focusDrawerPane5
    case focusDrawerPane6, focusDrawerPane7, focusDrawerPane8, focusDrawerPane9
    case detachDrawerPane
    case addDrawerPane
    case toggleDrawer
    case navigateDrawerPane
    case closeDrawerPane
    case openPaneLocationInBookmarkedEditor
    case openPaneLocationInFinder
    case openPaneLocationInEditorMenu
    case editPaneNote
    case copyCurrentPanePath
    // Repo commands
    case watchFolder, removeRepo
    case addRepoFavorite, removeRepoFavorite
    case openWorktree
    case openWorktreeInPane
    // Management layer
    case toggleManagementLayer
    case managementLayerFocusLeft
    case managementLayerFocusRight
    case managementLayerEnterDrawer
    case managementLayerExitDrawer
    case managementLayerOpenDrawer
    case managementLayerCreateTerminal
    case managementLayerCreateBrowser
    case managementLayerExit
    // Workspace commands
    case toggleSidebar
    case showInboxNotifications
    case toggleInboxNotificationSort
    case clearReadInboxNotifications
    case clearAllInboxNotifications
    case showPaneInboxNotifications
    case clearPaneInboxNotifications
    case showWorktreeSidebar
    case setRepoSidebarGroupingRepo
    case setRepoSidebarGroupingPane
    case setRepoSidebarGroupingTab
    case setRepoSidebarVisibilityMode
    case setRepoSidebarSortOrder
    case setInboxGroupingTab
    case setInboxGroupingRepo
    case setInboxGroupingPane
    case setInboxGroupingNone
    case setInboxRowStateFilter
    case setInboxContentMode
    case newFloatingTerminal
    // Window commands
    case newWindow
    case closeWindow
    // Search/navigation
    case showCommandBarEverything
    case showCommandBarCommands
    case showCommandBarPanes
    case showCommandBarRepos
    // Webview commands
    case openWebview
    case showBridgeReview
    case showBridgeFiles
    case openBridgeReviewInNewTab
    case openBridgeFilesInNewTab
    case signInGitHub
    case signInGoogle
    // Sidebar commands
    case filterSidebar
    case openNewTerminalInTab
}

extension AppCommand {
    var isScopeAwareDrawerShortcut: Bool {
        switch self {
        case .enterDrawer, .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown, .focusDrawerPaneRight:
            return true
        default:
            return false
        }
    }
}

// MARK: - SearchItemType

/// Types of items that can be searched and targeted by commands.
enum SearchItemType: String, CaseIterable {
    case repo
    case worktree
    case tab
    case pane
    case floatingTerminal
}

// MARK: - KeyBinding

/// A keyboard shortcut binding for a command.
struct KeyBinding: Codable, Hashable, Sendable {
    var key: String
    var modifiers: Set<Modifier>

    enum Modifier: String, Codable, Hashable, Sendable {
        case command
        case control
        case option
        case shift
    }
}

// MARK: - AppCommandSpec

/// Full command definition tying command identity, shortcut, display info, and context together.
struct AppCommandSpec {
    let command: AppCommand
    let shortcut: AppShortcut?
    let displayShortcutTrigger: ShortcutTrigger?
    let label: String
    let icon: CommandIcon
    let helpText: String
    let appliesTo: Set<SearchItemType>
    let requiresManagementLayer: Bool
    let visibleWhen: Set<FocusRequirement>
    let commandBarGroupName: String
    let commandBarGroupPriority: Int
    let isHiddenInCommandBar: Bool

    init(
        command: AppCommand,
        shortcut: AppShortcut? = nil,
        displayShortcutTrigger: ShortcutTrigger? = nil,
        label: String,
        icon: CommandIcon,
        helpText: String,
        appliesTo: Set<SearchItemType> = [],
        requiresManagementLayer: Bool = false,
        visibleWhen: Set<FocusRequirement> = [],
        commandBarGroupName: String = "Commands",
        commandBarGroupPriority: Int = 8,
        isHiddenInCommandBar: Bool = false
    ) {
        self.command = command
        self.shortcut = shortcut
        self.displayShortcutTrigger = displayShortcutTrigger
        self.label = label
        self.icon = icon
        self.helpText = helpText
        self.appliesTo = appliesTo
        self.requiresManagementLayer = requiresManagementLayer
        self.visibleWhen = visibleWhen
        self.commandBarGroupName = commandBarGroupName
        self.commandBarGroupPriority = commandBarGroupPriority
        self.isHiddenInCommandBar = isHiddenInCommandBar
    }

    var keyBinding: KeyBinding? { shortcut?.keyBinding }
    var commandBarShortcutTrigger: ShortcutTrigger? { displayShortcutTrigger ?? shortcut?.trigger }
}

/// Feature-facing access to App-owned command execution.
@MainActor
protocol AppCommandDispatching: AnyObject, Sendable {
    func dispatch(_ command: AppCommand)
    func dispatch(_ command: AppCommand, target: UUID, targetType: SearchItemType)
    func canDispatch(_ command: AppCommand) -> Bool
    func canDispatch(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool
    func bridgePaneCommandTarget(worktreeId: UUID) -> BridgePaneCommandTarget?
    func dispatchMovePaneToTab(sourcePaneId: UUID, sourceTabId: UUID?, targetTabId: UUID)
}
