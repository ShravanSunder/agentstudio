import AgentStudioProgrammaticControl
import AppKit
import Foundation
import Observation
import os

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
    case openBridgeReview
    case openBridgeFileView
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

// MARK: - KeyBinding + AppKit

extension KeyBinding {
    /// Convert modifiers to AppKit modifier mask
    var nsModifierMask: NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        for mod in modifiers {
            switch mod {
            case .command: mask.insert(.command)
            case .control: mask.insert(.control)
            case .option: mask.insert(.option)
            case .shift: mask.insert(.shift)
            }
        }
        return mask
    }

    /// Apply this key binding to an NSMenuItem
    func apply(to item: NSMenuItem) {
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = nsModifierMask
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
    let ipcExposure: AppCommandIPCExposure

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
        isHiddenInCommandBar: Bool = false,
        ipcExposure: AppCommandIPCExposure? = nil
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
        self.ipcExposure =
            ipcExposure
            ?? AppCommandIPCExposure.defaultInteractive(
                command: command,
                targetKinds: Self.ipcTargetKinds(for: appliesTo)
            )
    }

    var keyBinding: KeyBinding? { shortcut?.keyBinding }
    var commandBarShortcutTrigger: ShortcutTrigger? { displayShortcutTrigger ?? shortcut?.trigger }

    private static func ipcTargetKinds(for searchItemTypes: Set<SearchItemType>) -> [IPCHandleKind] {
        var targetKinds: [IPCHandleKind] = []
        if searchItemTypes.contains(.tab) {
            targetKinds.append(.tab)
        }
        if searchItemTypes.contains(.pane) || searchItemTypes.contains(.floatingTerminal) {
            targetKinds.append(.pane)
        }
        return targetKinds
    }
}

struct AppCommandIPCExposure: Equatable, Sendable {
    let executionModes: [IPCCommandExecutionMode]
    let targetKinds: [IPCHandleKind]
    let requiredPrivileges: [IPCPrivilegeClass]

    static func defaultInteractive(command: AppCommand, targetKinds: [IPCHandleKind]) -> Self {
        Self(
            executionModes: [.requiresInteractiveInput],
            targetKinds: targetKinds,
            requiredPrivileges: Self.defaultRequiredPrivileges(for: command)
        )
    }

    static func uiPresentation() -> Self {
        Self(
            executionModes: [.uiPresentation],
            targetKinds: [],
            requiredPrivileges: [.uiPresent]
        )
    }

    var commandListEntryIsHeadlessExecutable: Bool {
        executionModes.contains(.headless)
    }

    private static func defaultRequiredPrivileges(for command: AppCommand) -> [IPCPrivilegeClass] {
        switch command {
        case .closeTab, .breakUpTab, .renameTab, .newTerminalInTab, .newTab, .undoCloseTab,
            .selectTab, .nextTab, .prevTab, .selectTab1, .selectTab2, .selectTab3, .selectTab4,
            .selectTab5, .selectTab6, .selectTab7, .selectTab8, .selectTab9,
            .closePane, .extractPaneToTab, .movePaneToTab, .focusPane, .splitRight, .splitLeft,
            .equalizePanes, .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown,
            .focusNextPane, .focusPrevPane, .focusPane1, .focusPane2, .focusPane3, .focusPane4,
            .focusPane5, .focusPane6, .focusPane7, .focusPane8, .focusPane9, .toggleSplitZoom,
            .minimizePane, .expandPane, .switchArrangement, .previousArrangement, .nextArrangement,
            .cycleArrangement, .saveArrangement, .deleteArrangement, .renameArrangement, .enterDrawer,
            .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown, .focusDrawerPaneRight,
            .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
            .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
            .focusDrawerPane9, .detachDrawerPane, .addDrawerPane, .toggleDrawer, .navigateDrawerPane,
            .closeDrawerPane, .toggleManagementLayer, .managementLayerFocusLeft,
            .managementLayerFocusRight, .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal, .managementLayerCreateBrowser,
            .managementLayerExit, .toggleSidebar, .showInboxNotifications, .toggleInboxNotificationSort,
            .clearReadInboxNotifications, .clearAllInboxNotifications, .showPaneInboxNotifications,
            .clearPaneInboxNotifications, .showWorktreeSidebar, .newFloatingTerminal, .newWindow,
            .closeWindow, .openNewTerminalInTab:
            return [.layoutMutate]
        case .scrollToBottom, .scrollPageUp, .jumpToPreviousPrompt, .jumpToNextPrompt:
            return [.terminalInputWrite]
        case .editPaneNote, .watchFolder, .removeRepo, .openWorktree, .openWorktreeInPane,
            .openWebview, .openBridgeReview, .openBridgeFileView:
            return [.layoutMutate]
        case .openPaneLocationInBookmarkedEditor, .openPaneLocationInFinder, .openPaneLocationInEditorMenu,
            .copyCurrentPanePath, .signInGitHub, .signInGoogle, .filterSidebar, .showCommandBarEverything,
            .showCommandBarCommands, .showCommandBarPanes, .showCommandBarRepos:
            return [.workspaceRead]
        }
    }
}

// MARK: - WorkspaceCommandHandling

/// Protocol for objects that can execute commands.
@MainActor
protocol WorkspaceCommandHandling: AnyObject {
    /// Execute a contextual command (operates on the active/focused element)
    func execute(_ command: AppCommand)

    /// Execute a targeted command (operates on a specific element from search/command bar)
    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType)

    /// Query whether a command is currently available
    func canExecute(_ command: AppCommand) -> Bool

    /// Query whether a targeted command is currently available for a specific element.
    func canExecute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool

    /// Execute a direct pane extraction request that carries drag/drop placement details.
    func executeExtractPaneToTab(tabId: UUID, paneId: UUID, targetTabIndex: Int?)

    /// Execute a direct move-pane request with explicit source and destination identities.
    func executeMovePaneToTab(sourcePaneId: UUID, sourceTabId: UUID?, targetTabId: UUID)
}

/// Routes app-level commands that do not belong to the pane command handler.
@MainActor
protocol ShellCommandHandling: AnyObject {
    func canExecute(_ command: AppCommand) -> Bool
    func canExecute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool
    func execute(_ command: AppCommand) -> Bool
    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool

    /// Show the repo/worktree-scoped command bar for discovered checkout actions.
    func showRepoCommandBar()

    /// Refresh watched folders / worktree discovery from an app-level UI entry point.
    func refreshWorktrees()

    /// Restore focus to the active pane after transient sidebar/management UI work.
    func refocusActivePane()
}

@MainActor
extension WorkspaceCommandHandling {
    func canExecute(_ command: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool {
        canExecute(command)
    }
}

@MainActor
extension ShellCommandHandling {
    func canExecute(_ command: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool {
        canExecute(command)
    }
}

// MARK: - AppCommandDispatcher

/// Single execution point for all commands in the application.
/// Routes keyboard shortcuts, menu items, search result actions,
/// and management layer clicks through the same command system.
@Observable
@MainActor
final class AppCommandDispatcher {
    static let shared = AppCommandDispatcher()
    private static let logger = Logger(subsystem: "com.agentstudio", category: "AppCommandDispatcher")

    /// Registry of all command definitions
    private(set) var definitions: [AppCommand: AppCommandSpec] = [:]

    /// Active command handler (typically the tab/pane controller)
    weak var handler: WorkspaceCommandHandling?
    weak var appCommandRouter: ShellCommandHandling?

    private init() {
        registerDefaults()
    }

    // MARK: - Execution

    /// Execute a contextual command (operates on active element)
    func dispatch(_ command: AppCommand) {
        guard canDispatch(command) else {
            Self.logger.warning("Command dispatch rejected: \(command.rawValue, privacy: .public)")
            return
        }
        if appCommandRouter?.execute(command) == true {
            return
        }
        guard let handler else {
            Self.logger.warning("Command dispatch had no workspace handler: \(command.rawValue, privacy: .public)")
            return
        }
        handler.execute(command)
    }

    /// Execute a targeted command (operates on a specific element)
    func dispatch(_ command: AppCommand, target: UUID, targetType: SearchItemType) {
        guard canDispatch(command, target: target, targetType: targetType) else {
            Self.logger.warning(
                "Targeted command dispatch rejected: \(command.rawValue, privacy: .public) targetType=\(targetType.rawValue, privacy: .public)"
            )
            return
        }
        if appCommandRouter?.execute(command, target: target, targetType: targetType) == true {
            return
        }
        guard let handler else {
            Self.logger.warning(
                "Targeted command dispatch had no workspace handler: \(command.rawValue, privacy: .public)"
            )
            return
        }
        handler.execute(command, target: target, targetType: targetType)
    }

    /// Execute a drag/drop extract-pane request through the active command handler.
    func dispatchExtractPaneToTab(tabId: UUID, paneId: UUID, targetTabIndex: Int?) {
        guard canDispatch(.extractPaneToTab) else { return }
        handler?.executeExtractPaneToTab(tabId: tabId, paneId: paneId, targetTabIndex: targetTabIndex)
    }

    /// Execute a move-pane request with explicit source and destination identifiers.
    func dispatchMovePaneToTab(sourcePaneId: UUID, sourceTabId: UUID?, targetTabId: UUID) {
        guard canDispatch(.movePaneToTab) else { return }
        handler?.executeMovePaneToTab(
            sourcePaneId: sourcePaneId,
            sourceTabId: sourceTabId,
            targetTabId: targetTabId
        )
    }

    /// Check if a command can currently be executed
    func canDispatch(_ command: AppCommand) -> Bool {
        if let definition = definitions[command],
            definition.requiresManagementLayer,
            !atom(\.managementLayer).isActive
        {
            return false
        }
        let appCanExecute = appCommandRouter?.canExecute(command) ?? false
        let handlerCanExecute = handler?.canExecute(command) ?? false
        return appCanExecute || handlerCanExecute
    }

    func canDispatch(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool {
        if let definition = definitions[command],
            definition.requiresManagementLayer,
            !atom(\.managementLayer).isActive
        {
            return false
        }
        let appCanExecute = appCommandRouter?.canExecute(command, target: target, targetType: targetType) ?? false
        let handlerCanExecute = handler?.canExecute(command, target: target, targetType: targetType) ?? false
        return appCanExecute || handlerCanExecute
    }

    // MARK: - Lookup

    /// Get the definition for a command
    func definition(for command: AppCommand) -> AppCommandSpec {
        guard let definition = definitions[command] else {
            fatalError("Missing command spec for \(command.rawValue)")
        }
        return definition
    }

    /// Get commands available for a given item type
    func commands(for itemType: SearchItemType) -> [AppCommandSpec] {
        definitions.values.filter { $0.appliesTo.contains(itemType) }
    }

    // MARK: - Registration

    private func registerDefaults() {
        for def in AppCommand.allCases.map(\.definition) {
            definitions[def.command] = def
        }
    }
}
