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
    case openPaneLocationInBookmarkedEditor
    case openPaneLocationInFinder
    case openPaneLocationInEditorMenu
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
        label: String,
        icon: CommandIcon,
        helpText: String,
        appliesTo: Set<SearchItemType> = [],
        requiresManagementLayer: Bool = false,
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
        self.requiresManagementLayer = requiresManagementLayer
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

    /// Show the repo/worktree-scoped command bar for discovered checkout actions.
    func showRepoCommandBar()

    /// Refresh watched folders / worktree discovery from an app-level UI entry point.
    func refreshWorktrees()

    /// Restore focus to the active pane after transient sidebar/management UI work.
    func refocusActivePane()
}

// MARK: - CommandDispatcher

/// Single execution point for all commands in the application.
/// Routes keyboard shortcuts, menu items, search result actions,
/// and management layer clicks through the same command system.
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
            definition.requiresManagementLayer,
            !atom(\.managementLayer).isActive
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
extension AppCommand {
    enum CommandBarGroupPriority {
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
                icon: .system(.xmark),
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
                icon: .system(.rectangleSplit3x1),
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
                icon: .system(.pencil),
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
                icon: .system(.terminal),
                helpText: "Add a new terminal to the active tab",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .newTab:
            return CommandSpec(
                command: self,
                label: "New Tab",
                icon: .system(.plusSquare),
                helpText: "Create a new terminal tab",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .undoCloseTab:
            return CommandSpec(
                command: self,
                shortcut: .undoCloseTab,
                label: "Undo Close Tab",
                icon: .system(.arrowUturnBackward),
                helpText: "Restore the most recently closed tab",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .selectTab:
            return CommandSpec(
                command: self,
                label: "Select Tab",
                icon: .system(.rectangleStack),
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
                icon: .system(.chevronRight),
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
                icon: .system(.chevronLeft),
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
                icon: .system(.xmarkSquare),
                helpText: "Close the active pane",
                appliesTo: [.pane, .floatingTerminal],
                requiresManagementLayer: true,
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .extractPaneToTab:
            return CommandSpec(
                command: self,
                label: "Move Pane to New Tab",
                icon: .system(.arrowUpRightSquare),
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
                icon: .system(.arrowLeftAndRightSquare),
                helpText: "Move the active pane into another existing tab",
                appliesTo: [.pane],
                requiresManagementLayer: true,
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .focusPane:
            return CommandSpec(
                command: self,
                label: "Focus Pane",
                icon: .system(.scope),
                helpText: "Focus a specific pane",
                appliesTo: [.pane, .floatingTerminal],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane,
                isHiddenInCommandBar: true
            )
        case .scrollToBottom:
            return CommandSpec(
                command: self,
                shortcut: .scrollToBottom,
                label: "Scroll to Bottom",
                icon: .system(.arrowDownToLine),
                helpText: "Scroll the active terminal pane to the bottom of its scrollback",
                appliesTo: [.pane, .floatingTerminal],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .splitRight:
            return CommandSpec(
                command: self,
                label: "Split Right",
                icon: .system(.rectangleSplit1x2),
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
                icon: .system(.rectangleSplit1x2),
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
                icon: .system(.equalSquare),
                helpText: "Reset all pane sizes in the active tab to equal widths",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab, .hasMultiplePanes],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .focusPaneLeft:
            return focusDefinition(
                label: "Focus Pane Left",
                icon: .arrowLeft,
                helpText: "Move focus to the pane on the left"
            )
        case .focusPaneRight:
            return focusDefinition(
                label: "Focus Pane Right",
                icon: .arrowRight,
                helpText: "Move focus to the pane on the right"
            )
        case .focusPaneUp:
            return focusDefinition(
                label: "Focus Pane Up",
                icon: .arrowUp,
                helpText: "Move focus to the pane above"
            )
        case .focusPaneDown:
            return focusDefinition(
                label: "Focus Pane Down",
                icon: .arrowDown,
                helpText: "Move focus to the pane below"
            )
        case .focusNextPane:
            return focusDefinition(
                label: "Focus Next Pane",
                icon: .arrowRightCircle,
                helpText: "Move focus to the next pane"
            )
        case .focusPrevPane:
            return focusDefinition(
                label: "Focus Previous Pane",
                icon: .arrowLeftCircle,
                helpText: "Move focus to the previous pane"
            )
        case .toggleSplitZoom:
            return CommandSpec(
                command: self,
                label: "Toggle Split Zoom",
                icon: .system(.arrowUpLeftAndArrowDownRight),
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
                icon: .system(.minusCircle),
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
                icon: .system(.arrowUpLeftAndArrowDownRight),
                helpText: "Expand a minimized pane back into the layout",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .switchArrangement:
            return arrangementDefinition(
                label: "Switch Arrangement",
                icon: .rectangle3Group,
                helpText: "Switch the active tab to a saved arrangement"
            )
        case .saveArrangement:
            // Save Arrangement must stay visible with only the default arrangement so users can create their first custom layout.
            return CommandSpec(
                command: self,
                label: "Save Arrangement As...",
                icon: .system(.rectangle3GroupFill),
                helpText: "Save the current tab layout as a named arrangement",
                appliesTo: [.tab],
                visibleWhen: [.hasActiveTab],
                commandBarGroupName: "Tab",
                commandBarGroupPriority: CommandBarGroupPriority.tab
            )
        case .deleteArrangement:
            return arrangementDefinition(
                label: "Delete Arrangement",
                icon: .rectangle3GroupBubble,
                helpText: "Delete a saved arrangement from the active tab"
            )
        case .renameArrangement:
            return arrangementDefinition(
                label: "Rename Arrangement",
                icon: .pencil,
                helpText: "Rename a saved arrangement in the active tab"
            )
        case .addDrawerPane:
            return CommandSpec(
                command: self,
                shortcut: .addDrawerPane,
                label: "Add Drawer Pane",
                icon: .system(.rectangleBottomhalfInsetFilled),
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
                icon: .system(.rectangleExpandVertical),
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
                icon: .system(.arrowDownToLine),
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
                icon: .system(.xmarkRectanglePortrait),
                helpText: "Close a pane inside the active drawer",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane, .hasDrawerPanes],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .watchFolder:
            return CommandSpec(
                command: self,
                shortcut: nil,
                label: "Watch Folder",
                icon: .system(.folderFillBadgePlus),
                helpText: "Watch a folder and scan it for repositories",
                commandBarGroupName: "Repo",
                commandBarGroupPriority: CommandBarGroupPriority.repo
            )
        case .removeRepo:
            return CommandSpec(
                command: self,
                label: "Remove Repo",
                icon: .system(.folderBadgeMinus),
                helpText: "Remove a repository from the workspace",
                appliesTo: [.repo],
                commandBarGroupName: "Repo",
                commandBarGroupPriority: CommandBarGroupPriority.repo
            )
        case .openWorktree:
            return worktreeDefinition(
                label: "Open Worktree",
                icon: .terminal,
                helpText: "Open a worktree in a tab"
            )
        case .openWorktreeInPane:
            return worktreeDefinition(
                label: "Open Worktree in Pane",
                icon: .rectangleSplit2x1,
                helpText: "Open a worktree in a split pane"
            )
        case .openPaneLocationInBookmarkedEditor:
            return CommandSpec(
                command: self,
                shortcut: .openPaneLocationInBookmarkedEditor,
                label: "Open Pane Location in Bookmarked Editor",
                icon: .system(.chevronLeftForwardslashChevronRight),
                helpText: "Open the selected pane location in the bookmarked editor",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .openPaneLocationInFinder:
            return CommandSpec(
                command: self,
                shortcut: .openPaneLocationInFinder,
                label: "Open Pane Location in Finder",
                icon: .system(.finder),
                helpText: "Open the selected pane location in Finder",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .openPaneLocationInEditorMenu:
            return CommandSpec(
                command: self,
                shortcut: .openPaneLocationInEditorMenu,
                label: "Open In Menu",
                icon: .system(.chevronUpChevronDown),
                helpText: "Open the editor chooser for the selected pane",
                appliesTo: [.pane],
                visibleWhen: [.hasActivePane],
                commandBarGroupName: "Pane",
                commandBarGroupPriority: CommandBarGroupPriority.pane
            )
        case .toggleManagementLayer:
            return CommandSpec(
                command: self,
                shortcut: .toggleManagementLayer,
                label: "Manage Workspace",
                icon: .system(.rectangleSplit2x2),
                helpText: "Toggle workspace management mode",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .managementLayerFocusLeft:
            return managementDefinition(
                shortcut: .managementLayerFocusLeft,
                label: "Management Focus Left", icon: .arrowLeft, helpText: "Move focus left in management mode")
        case .managementLayerFocusRight:
            return managementDefinition(
                shortcut: .managementLayerFocusRight,
                label: "Management Focus Right", icon: .arrowRight, helpText: "Move focus right in management mode")
        case .managementLayerEnterDrawer:
            return managementDefinition(
                shortcut: .managementLayerEnterDrawer,
                label: "Management Enter Drawer", icon: .arrowDown,
                helpText: "Enter or expand the current drawer in management mode")
        case .managementLayerExitDrawer:
            return managementDefinition(
                shortcut: .managementLayerExitDrawer,
                label: "Management Exit Drawer", icon: .arrowUp,
                helpText: "Collapse the current drawer in management mode")
        case .managementLayerOpenDrawer:
            return managementDefinition(
                shortcut: .managementLayerOpenDrawer,
                label: "Management Open Drawer", icon: .rectangleExpandVertical,
                helpText: "Open the current drawer in management mode")
        case .managementLayerCreateTerminal:
            return managementDefinition(
                shortcut: .managementLayerCreateTerminal,
                label: "Management Create Terminal", icon: .plusSquare,
                helpText: "Create a terminal in the current management-mode context")
        case .managementLayerCreateBrowser:
            return managementDefinition(
                shortcut: .managementLayerCreateBrowser,
                label: "Management Create Browser", icon: .globe,
                helpText: "Create a browser in the current management-mode context")
        case .managementLayerExit:
            return managementDefinition(
                shortcut: .managementLayerExit,
                label: "Management Exit Mode", icon: .rectangleSplit2x2Fill,
                helpText: "Exit management mode")
        case .toggleSidebar:
            return CommandSpec(
                command: self,
                shortcut: .toggleSidebar,
                label: "Toggle Sidebar",
                icon: .system(.sidebarLeft),
                helpText: "Show or hide the sidebar",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .newFloatingTerminal:
            return CommandSpec(
                command: self,
                label: "New Floating Terminal",
                icon: .system(.terminalFill),
                helpText: "Open a new floating terminal",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .newWindow:
            return CommandSpec(
                command: self,
                shortcut: .newWindow,
                label: "New Window",
                icon: .system(.macwindowBadgePlus),
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
                icon: .system(.xmarkRectangle),
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
                icon: .system(.magnifyingglass),
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
                icon: .system(.command),
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
                icon: .system(.terminal),
                helpText: "Open the pane picker",
                commandBarGroupName: "Commands",
                commandBarGroupPriority: CommandBarGroupPriority.miscellaneous,
                isHiddenInCommandBar: true
            )
        case .showCommandBarRepos:
            return CommandSpec(
                command: self,
                shortcut: .newTab,
                label: "New Tab or Worktree",
                icon: .system(.folder),
                helpText: "Open the repo and worktree picker",
                commandBarGroupName: "Commands",
                commandBarGroupPriority: CommandBarGroupPriority.miscellaneous,
                isHiddenInCommandBar: true
            )
        case .openWebview:
            return CommandSpec(
                command: self,
                label: "Open New Webview Tab",
                icon: .system(.globe),
                helpText: "Open a new webview tab",
                commandBarGroupName: "Webview",
                commandBarGroupPriority: CommandBarGroupPriority.webview
            )
        case .signInGitHub:
            return CommandSpec(
                command: self,
                label: "Sign in to GitHub",
                icon: .system(.personBadgeKey),
                helpText: "Start GitHub sign-in",
                commandBarGroupName: "Auth",
                commandBarGroupPriority: CommandBarGroupPriority.auth,
                isHiddenInCommandBar: true
            )
        case .signInGoogle:
            return CommandSpec(
                command: self,
                label: "Sign in to Google",
                icon: .system(.personBadgeKey),
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
                icon: .system(.magnifyingglass),
                helpText: "Filter items in the sidebar",
                commandBarGroupName: "Window",
                commandBarGroupPriority: CommandBarGroupPriority.window
            )
        case .openNewTerminalInTab:
            return worktreeDefinition(
                label: "Open Terminal in New Tab",
                icon: .terminalFill,
                helpText: "Open a worktree in a fresh terminal tab"
            )
        }
    }
}
