import AppKit
import Foundation
import Observation

// MARK: - AppCommand

/// All available commands in the application.
/// Every action — keyboard shortcut, menu item, context menu, command bar, search result,
/// or management mode click — is backed by a command.
enum AppCommand: String, CaseIterable {
    // Tab commands
    case closeTab
    case breakUpTab
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

    // Workspace commands
    case toggleSidebar
    case newFloatingTerminal

    // Window commands
    case newWindow
    case closeWindow

    // Search/navigation
    case quickFind, commandBar

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

// MARK: - CommandDefinition

/// Full command definition tying command identity, shortcut, display info, and context together.
struct CommandDefinition {
    let command: AppCommand
    let keyBinding: KeyBinding?
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
        keyBinding: KeyBinding? = nil,
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
        self.keyBinding = keyBinding
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
}

// MARK: - CommandHandler

/// Protocol for objects that can execute commands.
@MainActor
protocol CommandHandler: AnyObject {
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
protocol AppCommandRouting: AnyObject {
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

    /// Registry of all command definitions
    private(set) var definitions: [AppCommand: CommandDefinition] = [:]

    /// Active command handler (typically the tab/pane controller)
    weak var handler: CommandHandler?
    weak var appCommandRouter: AppCommandRouting?

    private init() {
        registerDefaults()
    }

    // MARK: - Execution

    /// Execute a contextual command (operates on active element)
    func dispatch(_ command: AppCommand) {
        guard canDispatch(command) else { return }
        if appCommandRouter?.execute(command) == true {
            return
        }
        handler?.execute(command)
    }

    /// Execute a targeted command (operates on a specific element)
    func dispatch(_ command: AppCommand, target: UUID, targetType: SearchItemType) {
        guard canDispatch(command) else { return }
        if appCommandRouter?.execute(command, target: target, targetType: targetType) == true {
            return
        }
        handler?.execute(command, target: target, targetType: targetType)
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
    func definition(for command: AppCommand) -> CommandDefinition {
        guard let definition = definitions[command] else {
            preconditionFailure("Missing command definition for \(command.rawValue)")
        }
        return definition
    }

    /// Get commands available for a given item type
    func commands(for itemType: SearchItemType) -> [CommandDefinition] {
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
    /// Ordered array of tab selection commands (⌘1 through ⌘9)
    static let selectTabCommands: [AppCommand] = [
        .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
        .selectTab6, .selectTab7, .selectTab8, .selectTab9,
    ]

    var definition: CommandDefinition {
        switch self {
        case .closeTab:
            return CommandDefinition(
                command: self,
                keyBinding: KeyBinding(key: "w", modifiers: [.command]),
                label: "Close Tab",
                icon: "xmark",
                helpText: "Close the active tab",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: 2
            )
        case .breakUpTab:
            return CommandDefinition(
                command: self,
                label: "Split Tab Into Individuals",
                icon: "rectangle.split.3x1",
                helpText: "Split each visible pane in the active tab into its own tab",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab, .hasMultiplePanes],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: 2
            )
        case .newTerminalInTab:
            return CommandDefinition(
                command: self,
                label: "Add Terminal to Tab",
                icon: "terminal",
                helpText: "Add a new terminal to the active tab",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: 2
            )
        case .newTab:
            return CommandDefinition(
                command: self,
                keyBinding: KeyBinding(key: "t", modifiers: [.command]),
                label: "New Tab",
                icon: "plus.square",
                helpText: "Create a new tab",
                commandBarGroupName: "Window",
                commandBarGroupPriority: 4
            )
        case .undoCloseTab:
            return CommandDefinition(
                command: self,
                keyBinding: KeyBinding(key: "t", modifiers: [.command, .shift]),
                label: "Undo Close Tab",
                icon: "arrow.uturn.backward",
                helpText: "Restore the most recently closed tab",
                commandBarGroupName: "Window",
                commandBarGroupPriority: 4
            )
        case .selectTab:
            return CommandDefinition(
                command: self,
                label: "Select Tab",
                icon: "rectangle.stack",
                helpText: "Select a specific tab",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: 2,
                isHiddenInCommandBar: true
            )
        case .nextTab:
            return CommandDefinition(
                command: self,
                keyBinding: KeyBinding(key: "]", modifiers: [.command, .shift]),
                label: "Next Tab",
                icon: "chevron.right",
                helpText: "Move to the next tab",
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: 2
            )
        case .prevTab:
            return CommandDefinition(
                command: self,
                keyBinding: KeyBinding(key: "[", modifiers: [.command, .shift]),
                label: "Previous Tab",
                icon: "chevron.left",
                helpText: "Move to the previous tab",
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: 2
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
            return CommandDefinition(
                command: self,
                label: "Close Pane",
                icon: "xmark.square",
                helpText: "Close the active pane",
                appliesTo: [.pane, .floatingTerminal],
                requiresManagementMode: true,
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: 0
            )
        case .extractPaneToTab:
            return CommandDefinition(
                command: self,
                label: "Move Pane to New Tab",
                icon: "arrow.up.right.square",
                helpText: "Move the active pane into a new tab",
                appliesTo: [.pane, .floatingTerminal],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: 0
            )
        case .movePaneToTab:
            return CommandDefinition(
                command: self,
                label: "Move Pane to Existing Tab",
                icon: "arrow.left.and.right.square",
                helpText: "Move the active pane into another existing tab",
                appliesTo: [.pane],
                requiresManagementMode: true,
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: 0
            )
        case .focusPane:
            return CommandDefinition(
                command: self,
                label: "Focus Pane",
                icon: "scope",
                helpText: "Focus a specific pane",
                appliesTo: [.pane, .floatingTerminal],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: 0,
                isHiddenInCommandBar: true
            )
        case .splitRight:
            return CommandDefinition(
                command: self,
                label: "Split Right",
                icon: "rectangle.split.1x2",
                helpText: "Split the active pane to the right",
                appliesTo: [.pane, .tab],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: 0
            )
        case .splitLeft:
            return CommandDefinition(
                command: self,
                label: "Split Left",
                icon: "rectangle.split.1x2",
                helpText: "Split the active pane to the left",
                appliesTo: [.pane, .tab],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: 0
            )
        case .equalizePanes:
            return CommandDefinition(
                command: self,
                label: "Equalize Panes",
                icon: "equal.square",
                helpText: "Reset all pane sizes in the active tab to equal widths",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: 0
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
            return CommandDefinition(
                command: self,
                label: "Toggle Split Zoom",
                icon: "arrow.up.left.and.arrow.down.right.magnifyingglass",
                helpText: "Toggle zoom for the active pane",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane, .hasMultiplePanes],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: 0
            )
        case .minimizePane:
            return CommandDefinition(
                command: self,
                label: "Minimize Pane",
                icon: "minus.circle",
                helpText: "Minimize the active pane",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: 0
            )
        case .expandPane:
            return CommandDefinition(
                command: self,
                label: "Expand Pane",
                icon: "arrow.up.left.and.arrow.down.right",
                helpText: "Expand a minimized pane back into the layout",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: 0
            )
        case .switchArrangement:
            return arrangementDefinition(
                label: "Switch Arrangement",
                icon: "rectangle.3.group",
                helpText: "Switch the active tab to a saved arrangement"
            )
        case .saveArrangement:
            // Save Arrangement must stay visible with only the default arrangement so users can create their first custom layout.
            return CommandDefinition(
                command: self,
                label: "Save Arrangement As...",
                icon: "rectangle.3.group.fill",
                helpText: "Save the current tab layout as a named arrangement",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: 2
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
            return CommandDefinition(
                command: self,
                label: "Add Drawer Pane",
                icon: "rectangle.bottomhalf.inset.filled",
                helpText: "Add a drawer pane to the active pane",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: 0
            )
        case .toggleDrawer:
            return CommandDefinition(
                command: self,
                label: "Toggle Drawer",
                icon: "rectangle.expand.vertical",
                helpText: "Expand or collapse the active pane drawer",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: 0
            )
        case .navigateDrawerPane:
            return CommandDefinition(
                command: self,
                label: "Switch Drawer Pane",
                icon: "arrow.down.to.line",
                helpText: "Switch to a pane inside the active drawer",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane, .hasDrawerPanes],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: 0
            )
        case .closeDrawerPane:
            return CommandDefinition(
                command: self,
                label: "Close Drawer Pane",
                icon: "xmark.rectangle.portrait",
                helpText: "Close a pane inside the active drawer",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane, .hasDrawerPanes],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: 0
            )
        case .addRepo:
            return CommandDefinition(
                command: self,
                keyBinding: KeyBinding(key: "O", modifiers: [.command, .shift]),
                label: "Add Repo",
                icon: "folder.badge.plus",
                helpText: "Add a repository directly to the workspace",
                appliesTo: [.repo],
                commandBarGroupName: "Repo",
                commandBarGroupPriority: 3
            )
        case .addFolder:
            return CommandDefinition(
                command: self,
                keyBinding: KeyBinding(key: "O", modifiers: [.command, .shift, .option]),
                label: "Add Folder",
                icon: "folder.badge.questionmark",
                helpText: "Add a folder to scan for repositories",
                commandBarGroupName: "Repo",
                commandBarGroupPriority: 3
            )
        case .removeRepo:
            return CommandDefinition(
                command: self,
                label: "Remove Repo",
                icon: "folder.badge.minus",
                helpText: "Remove a repository from the workspace",
                appliesTo: [.repo],
                commandBarGroupName: "Repo",
                commandBarGroupPriority: 3
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
            return CommandDefinition(
                command: self,
                keyBinding: KeyBinding(key: "e", modifiers: [.command]),
                label: "Manage Workspace",
                icon: "rectangle.split.2x2",
                helpText: "Toggle workspace management mode",
                commandBarGroupName: "Window",
                commandBarGroupPriority: 4
            )
        case .toggleSidebar:
            return CommandDefinition(
                command: self,
                keyBinding: KeyBinding(key: "s", modifiers: [.command, .shift]),
                label: "Toggle Sidebar",
                icon: "sidebar.left",
                helpText: "Show or hide the sidebar",
                commandBarGroupName: "Window",
                commandBarGroupPriority: 4
            )
        case .newFloatingTerminal:
            return CommandDefinition(
                command: self,
                label: "New Floating Terminal",
                icon: "terminal.fill",
                helpText: "Open a new floating terminal",
                commandBarGroupName: "Window",
                commandBarGroupPriority: 4
            )
        case .newWindow:
            return CommandDefinition(
                command: self,
                keyBinding: KeyBinding(key: "n", modifiers: [.command]),
                label: "New Window",
                icon: "macwindow.badge.plus",
                helpText: "Open a new application window",
                commandBarGroupName: "Window",
                commandBarGroupPriority: 4,
                isHiddenInCommandBar: true
            )
        case .closeWindow:
            return CommandDefinition(
                command: self,
                keyBinding: KeyBinding(key: "W", modifiers: [.command, .shift]),
                label: "Close Window",
                icon: "xmark.rectangle",
                helpText: "Close the current application window",
                commandBarGroupName: "Window",
                commandBarGroupPriority: 4,
                isHiddenInCommandBar: true
            )
        case .quickFind:
            return CommandDefinition(
                command: self,
                label: "Quick Find",
                icon: "magnifyingglass",
                helpText: "Open quick find",
                commandBarGroupName: "Commands",
                commandBarGroupPriority: 7,
                isHiddenInCommandBar: true
            )
        case .commandBar:
            return CommandDefinition(
                command: self,
                label: "Command Palette",
                icon: "command",
                helpText: "Open the command palette",
                commandBarGroupName: "Commands",
                commandBarGroupPriority: 7,
                isHiddenInCommandBar: true
            )
        case .openWebview:
            return CommandDefinition(
                command: self,
                label: "Open New Webview Tab",
                icon: "globe",
                helpText: "Open a new webview tab",
                commandBarGroupName: "Webview",
                commandBarGroupPriority: 5
            )
        case .signInGitHub:
            return CommandDefinition(
                command: self,
                label: "Sign in to GitHub",
                icon: "person.badge.key",
                helpText: "Start GitHub sign-in",
                commandBarGroupName: "Auth",
                commandBarGroupPriority: 6,
                isHiddenInCommandBar: true
            )
        case .signInGoogle:
            return CommandDefinition(
                command: self,
                label: "Sign in to Google",
                icon: "person.badge.key",
                helpText: "Start Google sign-in",
                commandBarGroupName: "Auth",
                commandBarGroupPriority: 6,
                isHiddenInCommandBar: true
            )
        case .filterSidebar:
            return CommandDefinition(
                command: self,
                keyBinding: KeyBinding(key: "f", modifiers: [.command, .shift]),
                label: "Filter Sidebar",
                icon: "magnifyingglass",
                helpText: "Filter items in the sidebar",
                commandBarGroupName: "Window",
                commandBarGroupPriority: 4
            )
        case .openNewTerminalInTab:
            return worktreeDefinition(
                label: "Open Terminal in New Tab",
                icon: "terminal.fill",
                helpText: "Open a worktree in a fresh terminal tab"
            )
        }
    }

    private func hiddenTabSelectionDefinition(index: Int) -> CommandDefinition {
        CommandDefinition(
            command: self,
            keyBinding: KeyBinding(key: "\(index)", modifiers: [.command]),
            label: "Select Tab \(index)",
            helpText: "Select tab \(index)",
            visibleWhen: [.hasActiveTab],
            isHiddenInCommandBar: true
        )
    }

    private func focusDefinition(label: String, icon: String, helpText: String) -> CommandDefinition {
        CommandDefinition(
            command: self,
            label: label,
            icon: icon,
            helpText: helpText,
            visibleWhen: [.hasActiveTab, .hasMultiplePanes],
            commandBarGroupName: "Focus",
            commandBarGroupPriority: 1
        )
    }

    private func arrangementDefinition(label: String, icon: String, helpText: String) -> CommandDefinition {
        CommandDefinition(
            command: self,
            label: label,
            icon: icon,
            helpText: helpText,
            appliesTo: [.tab],
            visibleWhen: [.hasActiveTab, .hasArrangements],
            commandBarGroupName: "Tab",
            commandBarGroupPriority: 2
        )
    }

    private func worktreeDefinition(label: String, icon: String, helpText: String) -> CommandDefinition {
        CommandDefinition(
            command: self,
            label: label,
            icon: icon,
            helpText: helpText,
            appliesTo: [.worktree],
            commandBarGroupName: "Repo",
            commandBarGroupPriority: 3
        )
    }
}
