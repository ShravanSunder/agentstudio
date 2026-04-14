import AppKit
import Foundation
import Observation
import os

// MARK: - AppCommand

/// All available commands in the application.
/// Every action — keyboard shortcut, menu item, context menu, command bar, search result,
/// or management mode click — is backed by a command.
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
    case splitRight, splitLeft
    case equalizePanes
    case focusPaneLeft, focusPaneRight, focusPaneUp, focusPaneDown
    case focusNextPane, focusPrevPane
    case toggleSplitZoom
    case minimizePane
    case expandPane

    // Arrangement commands
    case switchArrangement
    case saveArrangement
    case deleteArrangement
    case renameArrangement

    // Drawer commands
    case addDrawerPane
    case toggleDrawer
    case navigateDrawerPane
    case closeDrawerPane

    // Repo commands
    case addRepo, addFolder, removeRepo
    case openWorktree
    case openWorktreeInPane

    // Management mode
    case toggleManagementMode
    case managementFocusLeft
    case managementFocusRight
    case managementEnterDrawer
    case managementExitDrawer
    case managementOpenDrawer
    case managementCreateTerminal
    case managementCreateBrowser
    case managementExitMode

    // Workspace commands
    case toggleSidebar
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
    case signInGitHub
    case signInGoogle

    // Sidebar commands
    case filterSidebar
    case openNewTerminalInTab
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
struct KeyBinding: Codable, Hashable {
    var key: String
    var modifiers: Set<Modifier>

    enum Modifier: String, Codable, Hashable {
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

// MARK: - CommandSpec

/// Full command definition tying command identity, shortcut, display info, and context together.
struct CommandSpec {
    let command: AppCommand
    let shortcut: AppShortcut?
    let label: String
    let icon: String?
    let helpText: String
    let appliesTo: Set<SearchItemType>
    let requiresManagementMode: Bool
    let visibleWhen: Set<FocusRequirement>
    let commandBarGroupName: String
    let commandBarGroupPriority: Int
    let isHiddenInCommandBar: Bool

    init(
        command: AppCommand,
        shortcut: AppShortcut? = nil,
        label: String,
        icon: String? = nil,
        helpText: String,
        appliesTo: Set<SearchItemType> = [],
        requiresManagementMode: Bool = false,
        visibleWhen: Set<FocusRequirement> = [],
        commandBarGroupName: String = "Commands",
        commandBarGroupPriority: Int = 7,
        isHiddenInCommandBar: Bool = false
    ) {
        self.command = command
        self.shortcut = shortcut
        self.label = label
        self.icon = icon
        self.helpText = helpText
        self.appliesTo = appliesTo
        self.requiresManagementMode = requiresManagementMode
        self.visibleWhen = visibleWhen
        self.commandBarGroupName = commandBarGroupName
        self.commandBarGroupPriority = commandBarGroupPriority
        self.isHiddenInCommandBar = isHiddenInCommandBar
    }

    var keyBinding: KeyBinding? { shortcut?.keyBinding }
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

    /// Execute a direct pane extraction request that carries drag/drop placement details.
    func executeExtractPaneToTab(tabId: UUID, paneId: UUID, targetTabIndex: Int?)

    /// Execute a direct move-pane request with explicit source and destination identities.
    func executeMovePaneToTab(sourcePaneId: UUID, sourceTabId: UUID?, targetTabId: UUID)
}

/// Routes app-level commands that do not belong to the pane command handler.
@MainActor
protocol ShellCommandHandling: AnyObject {
    func canExecute(_ command: AppCommand) -> Bool
    func execute(_ command: AppCommand) -> Bool
    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool

    /// Show the repo-scoped command bar for "open repo in tab" affordances.
    func showRepoCommandBar()

    /// Refresh watched folders / worktree discovery from an app-level UI entry point.
    func refreshWorktrees()

    /// Restore focus to the active pane after transient sidebar/management UI work.
    func refocusActivePane()
}

// MARK: - CommandDispatcher

/// Single execution point for all commands in the application.
/// Routes keyboard shortcuts, menu items, search result actions,
/// and management mode clicks through the same command system.
@Observable
@MainActor
final class CommandDispatcher {
    static let shared = CommandDispatcher()
    private static let logger = Logger(subsystem: "com.agentstudio", category: "CommandDispatcher")

    /// Registry of all command definitions
    private(set) var definitions: [AppCommand: CommandSpec] = [:]

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
        guard canDispatch(command) else {
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
            definition.requiresManagementMode,
            !atom(\.managementMode).isActive
        {
            return false
        }
        let appCanExecute = appCommandRouter?.canExecute(command) ?? false
        let handlerCanExecute = handler?.canExecute(command) ?? false
        return appCanExecute || handlerCanExecute
    }

    // MARK: - Lookup

    /// Get the definition for a command
    func definition(for command: AppCommand) -> CommandSpec {
        guard let definition = definitions[command] else {
            fatalError("Missing command spec for \(command.rawValue)")
        }
        return definition
    }

    /// Get commands available for a given item type
    func commands(for itemType: SearchItemType) -> [CommandSpec] {
        definitions.values.filter { $0.appliesTo.contains(itemType) }
    }

    // MARK: - Registration

    private func registerDefaults() {
        for def in AppCommand.allCases.map(\.definition) {
            definitions[def.command] = def
        }
    }
}

// MARK: - AppCommand Helpers

extension AppCommand {
    private enum CommandBarGroupPriority {
        static let pane = 0
        static let focus = 1
        static let tab = 2
        static let repo = 3
        static let window = 4
        static let webview = 5
        static let auth = 6
        static let miscellaneous = 7
    }

    /// Ordered array of tab selection commands (⌘1 through ⌘9)
    static let selectTabCommands: [AppCommand] = [
        .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
        .selectTab6, .selectTab7, .selectTab8, .selectTab9,
    ]

    var definition: CommandSpec {
        switch self {
        case .closeTab:
            return CommandSpec(
                command: self,
                shortcut: .closeTab,
                label: "Close Tab",
                icon: "xmark",
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
                icon: "rectangle.split.3x1",
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
                icon: "pencil",
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
                icon: "terminal",
                helpText: "Add a new terminal to the active tab",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .newTab:
            return CommandSpec(
                command: self,
                shortcut: .newTab,
                label: "New Tab",
                icon: "plus.square",
                helpText: "Create a new tab",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .undoCloseTab:
            return CommandSpec(
                command: self,
                shortcut: .undoCloseTab,
                label: "Undo Close Tab",
                icon: "arrow.uturn.backward",
                helpText: "Restore the most recently closed tab",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .selectTab:
            return CommandSpec(
                command: self,
                label: "Select Tab",
                icon: "rectangle.stack",
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
                icon: "chevron.right",
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
                icon: "chevron.left",
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
                icon: "xmark.square",
                helpText: "Close the active pane",
                appliesTo: [.pane, .floatingTerminal],
                requiresManagementMode: true,
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .extractPaneToTab:
            return CommandSpec(
                command: self,
                label: "Move Pane to New Tab",
                icon: "arrow.up.right.square",
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
                icon: "arrow.left.and.right.square",
                helpText: "Move the active pane into another existing tab",
                appliesTo: [.pane],
                requiresManagementMode: true,
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .focusPane:
            return CommandSpec(
                command: self,
                label: "Focus Pane",
                icon: "scope",
                helpText: "Focus a specific pane",
                appliesTo: [.pane, .floatingTerminal],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane,
                isHiddenInCommandBar: true
            )
        case .splitRight:
            return CommandSpec(
                command: self,
                label: "Split Right",
                icon: "rectangle.split.1x2",
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
                icon: "rectangle.split.1x2",
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
                icon: "equal.square",
                helpText: "Reset all pane sizes in the active tab to equal widths",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab, .hasMultiplePanes],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .focusPaneLeft:
            return focusDefinition(
                label: "Focus Pane Left",
                icon: "arrow.left",
                helpText: "Move focus to the pane on the left"
            )
        case .focusPaneRight:
            return focusDefinition(
                label: "Focus Pane Right",
                icon: "arrow.right",
                helpText: "Move focus to the pane on the right"
            )
        case .focusPaneUp:
            return focusDefinition(
                label: "Focus Pane Up",
                icon: "arrow.up",
                helpText: "Move focus to the pane above"
            )
        case .focusPaneDown:
            return focusDefinition(
                label: "Focus Pane Down",
                icon: "arrow.down",
                helpText: "Move focus to the pane below"
            )
        case .focusNextPane:
            return focusDefinition(
                label: "Focus Next Pane",
                icon: "arrow.right.circle",
                helpText: "Move focus to the next pane"
            )
        case .focusPrevPane:
            return focusDefinition(
                label: "Focus Previous Pane",
                icon: "arrow.left.circle",
                helpText: "Move focus to the previous pane"
            )
        case .toggleSplitZoom:
            return CommandSpec(
                command: self,
                label: "Toggle Split Zoom",
                icon: "arrow.up.left.and.arrow.down.right.magnifyingglass",
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
                icon: "minus.circle",
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
                icon: "arrow.up.left.and.arrow.down.right",
                helpText: "Expand a minimized pane back into the layout",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .switchArrangement:
            return arrangementDefinition(
                label: "Switch Arrangement",
                icon: "rectangle.3.group",
                helpText: "Switch the active tab to a saved arrangement"
            )
        case .saveArrangement:
            // Save Arrangement must stay visible with only the default arrangement so users can create their first custom layout.
            return CommandSpec(
                command: self,
                label: "Save Arrangement As...",
                icon: "rectangle.3.group.fill",
                helpText: "Save the current tab layout as a named arrangement",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .deleteArrangement:
            return arrangementDefinition(
                label: "Delete Arrangement",
                icon: "rectangle.3.group.bubble",
                helpText: "Delete a saved arrangement from the active tab"
            )
        case .renameArrangement:
            return arrangementDefinition(
                label: "Rename Arrangement",
                icon: "pencil",
                helpText: "Rename a saved arrangement in the active tab"
            )
        case .addDrawerPane:
            return CommandSpec(
                command: self,
                shortcut: .addDrawerPane,
                label: "Add Drawer Pane",
                icon: "rectangle.bottomhalf.inset.filled",
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
                icon: "rectangle.expand.vertical",
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
                icon: "arrow.down.to.line",
                helpText: "Switch to a pane inside the active drawer",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane, .hasDrawerPanes],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .closeDrawerPane:
            return CommandSpec(
                command: self,
                label: "Close Drawer Pane",
                icon: "xmark.rectangle.portrait",
                helpText: "Close a pane inside the active drawer",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane, .hasDrawerPanes],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .addRepo:
            return CommandSpec(
                command: self,
                shortcut: .addRepo,
                label: "Add Repo",
                icon: "folder.badge.plus",
                helpText: "Add a repository directly to the workspace",
                appliesTo: [.repo],
                commandBarGroupName: "Repo",
                commandBarGroupPriority: CommandBarGroupPriority.repo
            )
        case .addFolder:
            return CommandSpec(
                command: self,
                shortcut: .addFolder,
                label: "Add Folder",
                icon: "folder.badge.questionmark",
                helpText: "Add a folder to scan for repositories",
                commandBarGroupName: "Repo",
                commandBarGroupPriority: CommandBarGroupPriority.repo
            )
        case .removeRepo:
            return CommandSpec(
                command: self,
                label: "Remove Repo",
                icon: "folder.badge.minus",
                helpText: "Remove a repository from the workspace",
                appliesTo: [.repo],
                commandBarGroupName: "Repo",
                commandBarGroupPriority: CommandBarGroupPriority.repo
            )
        case .openWorktree:
            return worktreeDefinition(
                label: "Open Worktree",
                icon: "terminal",
                helpText: "Open a worktree in a tab"
            )
        case .openWorktreeInPane:
            return worktreeDefinition(
                label: "Open Worktree in Pane",
                icon: "rectangle.split.2x1",
                helpText: "Open a worktree in a split pane"
            )
        case .toggleManagementMode:
            return CommandSpec(
                command: self,
                shortcut: .toggleManagementMode,
                label: "Manage Workspace",
                icon: "rectangle.split.2x2",
                helpText: "Toggle workspace management mode",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .managementFocusLeft:
            return managementDefinition(
                shortcut: .managementFocusLeft,
                label: "Management Focus Left", icon: "arrow.left", helpText: "Move focus left in management mode")
        case .managementFocusRight:
            return managementDefinition(
                shortcut: .managementFocusRight,
                label: "Management Focus Right", icon: "arrow.right", helpText: "Move focus right in management mode")
        case .managementEnterDrawer:
            return managementDefinition(
                shortcut: .managementEnterDrawer,
                label: "Management Enter Drawer", icon: "arrow.down",
                helpText: "Enter or expand the current drawer in management mode")
        case .managementExitDrawer:
            return managementDefinition(
                shortcut: .managementExitDrawer,
                label: "Management Exit Drawer", icon: "arrow.up",
                helpText: "Collapse the current drawer in management mode")
        case .managementOpenDrawer:
            return managementDefinition(
                shortcut: .managementOpenDrawer,
                label: "Management Open Drawer", icon: "rectangle.expand.vertical",
                helpText: "Open the current drawer in management mode")
        case .managementCreateTerminal:
            return managementDefinition(
                shortcut: .managementCreateTerminal,
                label: "Management Create Terminal", icon: "plus.square",
                helpText: "Create a terminal in the current management-mode context")
        case .managementCreateBrowser:
            return managementDefinition(
                shortcut: .managementCreateBrowser,
                label: "Management Create Browser", icon: "globe",
                helpText: "Create a browser in the current management-mode context")
        case .managementExitMode:
            return managementDefinition(
                shortcut: .managementExitMode,
                label: "Management Exit Mode", icon: "rectangle.split.2x2.fill",
                helpText: "Exit management mode")
        case .toggleSidebar:
            return CommandSpec(
                command: self,
                shortcut: .toggleSidebar,
                label: "Toggle Sidebar",
                icon: "sidebar.left",
                helpText: "Show or hide the sidebar",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .newFloatingTerminal:
            return CommandSpec(
                command: self,
                label: "New Floating Terminal",
                icon: "terminal.fill",
                helpText: "Open a new floating terminal",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .newWindow:
            return CommandSpec(
                command: self,
                shortcut: .newWindow,
                label: "New Window",
                icon: "macwindow.badge.plus",
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
                icon: "xmark.rectangle",
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
                icon: "magnifyingglass",
                helpText: "Open quick find",
                commandBarGroupName: "Commands",
                commandBarGroupPriority: CommandBarGroupPriority.miscellaneous,
                isHiddenInCommandBar: true
            )
        case .showCommandBarCommands:
            return CommandSpec(
                command: self,
                shortcut: .showCommandBarCommands,
                label: "Command Palette",
                icon: "command",
                helpText: "Open the command palette",
                commandBarGroupName: "Commands",
                commandBarGroupPriority: CommandBarGroupPriority.miscellaneous,
                isHiddenInCommandBar: true
            )
        case .showCommandBarPanes:
            return CommandSpec(
                command: self,
                shortcut: .showCommandBarPanes,
                label: "Go to Pane",
                icon: "terminal",
                helpText: "Open the pane picker",
                commandBarGroupName: "Commands",
                commandBarGroupPriority: CommandBarGroupPriority.miscellaneous,
                isHiddenInCommandBar: true
            )
        case .showCommandBarRepos:
            return CommandSpec(
                command: self,
                label: "Open Repo or Worktree",
                icon: "folder",
                helpText: "Open the repo picker",
                commandBarGroupName: "Commands",
                commandBarGroupPriority: CommandBarGroupPriority.miscellaneous,
                isHiddenInCommandBar: true
            )
        case .openWebview:
            return CommandSpec(
                command: self,
                label: "Open New Webview Tab",
                icon: "globe",
                helpText: "Open a new webview tab",
                commandBarGroupName: "Webview",
                commandBarGroupPriority: CommandBarGroupPriority.webview
            )
        case .signInGitHub:
            return CommandSpec(
                command: self,
                label: "Sign in to GitHub",
                icon: "person.badge.key",
                helpText: "Start GitHub sign-in",
                commandBarGroupName: "Auth",
                commandBarGroupPriority: CommandBarGroupPriority.auth,
                isHiddenInCommandBar: true
            )
        case .signInGoogle:
            return CommandSpec(
                command: self,
                label: "Sign in to Google",
                icon: "person.badge.key",
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
                icon: "magnifyingglass",
                helpText: "Filter items in the sidebar",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .openNewTerminalInTab:
            return worktreeDefinition(
                label: "Open Terminal in New Tab",
                icon: "terminal.fill",
                helpText: "Open a worktree in a fresh terminal tab"
            )
        }
    }

    private func hiddenTabSelectionDefinition(index: Int) -> CommandSpec {
        CommandSpec(
            command: self,
            shortcut: selectTabShortcut(index: index),
            label: "Select Tab \(index)",
            helpText: "Select tab \(index)",
            visibleWhen: [.hasActiveTab],
            commandBarGroupPriority: CommandBarGroupPriority.miscellaneous,
            isHiddenInCommandBar: true
        )
    }
    private func focusDefinition(label: String, icon: String, helpText: String) -> CommandSpec {
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
    private func arrangementDefinition(label: String, icon: String, helpText: String) -> CommandSpec {
        CommandSpec(
            command: self,
            label: label,
            icon: icon,
            helpText: helpText,
            appliesTo: [.tab],
            visibleWhen: [.hasActiveTab, .hasArrangements],
            commandBarGroupName: "Tab",
            commandBarGroupPriority: CommandBarGroupPriority.tab
        )
    }
    private func worktreeDefinition(label: String, icon: String, helpText: String) -> CommandSpec {
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
    private func managementDefinition(shortcut: AppShortcut, label: String, icon: String, helpText: String)
        -> CommandSpec
    {
        CommandSpec(
            command: self,
            shortcut: shortcut,
            label: label,
            icon: icon,
            helpText: helpText,
            requiresManagementMode: true,
            isHiddenInCommandBar: true
        )
    }
    private func selectTabShortcut(index: Int) -> AppShortcut {
        switch index {
        case 1: return .selectTab1
        case 2: return .selectTab2
        case 3: return .selectTab3
        case 4: return .selectTab4
        case 5: return .selectTab5
        case 6: return .selectTab6
        case 7: return .selectTab7
        case 8: return .selectTab8
        case 9: return .selectTab9
        default:
            preconditionFailure("Unsupported tab shortcut index \(index)")
        }
    }
}
