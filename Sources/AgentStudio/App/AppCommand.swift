// swiftlint:disable function_body_length
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
    case nextTab
    case prevTab
    case selectTab1, selectTab2, selectTab3, selectTab4, selectTab5
    case selectTab6, selectTab7, selectTab8, selectTab9

    // Pane commands
    case closePane
    case extractPaneToTab
    case splitRight, splitBelow, splitLeft, splitAbove
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
    case addRepo, removeRepo, refreshWorktrees

    // Edit mode
    case toggleEditMode

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
    var keyBinding: KeyBinding?
    let label: String
    let icon: String?
    let appliesTo: Set<SearchItemType>
    let requiresManagementMode: Bool

    init(
        command: AppCommand,
        keyBinding: KeyBinding? = nil,
        label: String,
        icon: String? = nil,
        appliesTo: Set<SearchItemType> = [],
        requiresManagementMode: Bool = false
    ) {
        self.command = command
        self.keyBinding = keyBinding
        self.label = label
        self.icon = icon
        self.appliesTo = appliesTo
        self.requiresManagementMode = requiresManagementMode
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

    private init() {
        registerDefaults()
    }

    // MARK: - Execution

    /// Execute a contextual command (operates on active element)
    func dispatch(_ command: AppCommand) {
        guard canDispatch(command) else { return }
        handler?.execute(command)
    }

    /// Execute a targeted command (operates on a specific element)
    func dispatch(_ command: AppCommand, target: UUID, targetType: SearchItemType) {
        guard canDispatch(command) else { return }
        handler?.execute(command, target: target, targetType: targetType)
    }

    /// Check if a command can currently be executed
    func canDispatch(_ command: AppCommand) -> Bool {
        handler?.canExecute(command) ?? false
    }

    // MARK: - Lookup

    /// Get the definition for a command
    func definition(for command: AppCommand) -> CommandDefinition? {
        definitions[command]
    }

    /// Get commands available for a given item type
    func commands(for itemType: SearchItemType) -> [CommandDefinition] {
        definitions.values.filter { $0.appliesTo.contains(itemType) }
    }

    // MARK: - Registration

    private func registerDefaults() {
        let defs: [CommandDefinition] = [
            // Tab commands
            CommandDefinition(
                command: .closeTab,
                keyBinding: KeyBinding(key: "w", modifiers: [.command]),
                label: "Close Tab",
                icon: "xmark",
                appliesTo: [.tab]
            ),
            CommandDefinition(
                command: .breakUpTab,
                label: "Break Up Tab",
                icon: "rectangle.split.3x1",
                appliesTo: [.tab]
            ),
            CommandDefinition(
                command: .newTerminalInTab,
                label: "New Terminal in Tab",
                icon: "terminal",
                appliesTo: [.tab]
            ),
            CommandDefinition(
                command: .nextTab,
                keyBinding: KeyBinding(key: "]", modifiers: [.command, .shift]),
                label: "Next Tab",
                icon: "chevron.right"
            ),
            CommandDefinition(
                command: .prevTab,
                keyBinding: KeyBinding(key: "[", modifiers: [.command, .shift]),
                label: "Previous Tab",
                icon: "chevron.left"
            ),

            // Pane commands
            CommandDefinition(
                command: .closePane,
                label: "Close Pane",
                icon: "xmark.square",
                appliesTo: [.pane, .floatingTerminal],
                requiresManagementMode: true
            ),
            CommandDefinition(
                command: .extractPaneToTab,
                label: "Extract Pane to Tab",
                icon: "arrow.up.right.square",
                appliesTo: [.pane, .floatingTerminal]
            ),
            CommandDefinition(
                command: .splitRight,
                label: "Split Right",
                icon: "rectangle.split.1x2",
                appliesTo: [.pane, .tab]
            ),
            CommandDefinition(
                command: .splitLeft,
                label: "Split Left",
                icon: "rectangle.split.1x2",
                appliesTo: [.pane, .tab]
            ),
            CommandDefinition(
                command: .equalizePanes,
                label: "Equalize Panes",
                icon: "equal.square",
                appliesTo: [.tab]
            ),
            CommandDefinition(
                command: .focusPaneLeft,
                label: "Focus Pane Left",
                icon: "arrow.left"
            ),
            CommandDefinition(
                command: .focusPaneRight,
                label: "Focus Pane Right",
                icon: "arrow.right"
            ),
            CommandDefinition(
                command: .focusPaneUp,
                label: "Focus Pane Up",
                icon: "arrow.up"
            ),
            CommandDefinition(
                command: .focusPaneDown,
                label: "Focus Pane Down",
                icon: "arrow.down"
            ),
            CommandDefinition(
                command: .focusNextPane,
                label: "Focus Next Pane",
                icon: "arrow.right.circle"
            ),
            CommandDefinition(
                command: .focusPrevPane,
                label: "Focus Previous Pane",
                icon: "arrow.left.circle"
            ),

            // Minimize / Expand
            CommandDefinition(
                command: .minimizePane,
                label: "Minimize Pane",
                icon: "minus.circle",
                appliesTo: [.pane]
            ),
            CommandDefinition(
                command: .expandPane,
                label: "Expand Pane",
                icon: "arrow.up.left.and.arrow.down.right",
                appliesTo: [.pane]
            ),

            // Arrangement commands
            CommandDefinition(
                command: .switchArrangement,
                label: "Switch Arrangement",
                icon: "rectangle.3.group",
                appliesTo: [.tab]
            ),
            CommandDefinition(
                command: .saveArrangement,
                label: "Save Arrangement As...",
                icon: "rectangle.3.group.fill",
                appliesTo: [.tab]
            ),
            CommandDefinition(
                command: .deleteArrangement,
                label: "Delete Arrangement",
                icon: "rectangle.3.group.bubble",
                appliesTo: [.tab]
            ),
            CommandDefinition(
                command: .renameArrangement,
                label: "Rename Arrangement",
                icon: "pencil",
                appliesTo: [.tab]
            ),

            // Drawer commands
            CommandDefinition(
                command: .addDrawerPane,
                label: "Add Drawer Pane",
                icon: "rectangle.bottomhalf.inset.filled",
                appliesTo: [.pane]
            ),
            CommandDefinition(
                command: .toggleDrawer,
                label: "Toggle Drawer",
                icon: "rectangle.expand.vertical",
                appliesTo: [.pane]
            ),
            CommandDefinition(
                command: .navigateDrawerPane,
                label: "Navigate to Drawer Pane",
                icon: "arrow.down.to.line",
                appliesTo: [.pane]
            ),
            CommandDefinition(
                command: .closeDrawerPane,
                label: "Close Drawer Pane",
                icon: "xmark.rectangle.portrait",
                appliesTo: [.pane]
            ),

            // Repo commands
            CommandDefinition(
                command: .addRepo,
                keyBinding: KeyBinding(key: "O", modifiers: [.command, .shift]),
                label: "Add Repo",
                icon: "folder.badge.plus",
                appliesTo: [.repo]
            ),
            CommandDefinition(
                command: .removeRepo,
                label: "Remove Repo",
                icon: "folder.badge.minus",
                appliesTo: [.repo]
            ),
            CommandDefinition(
                command: .refreshWorktrees,
                label: "Refresh Worktrees",
                icon: "arrow.clockwise",
                appliesTo: [.repo]
            ),

            // Edit mode
            CommandDefinition(
                command: .toggleEditMode,
                keyBinding: KeyBinding(key: "e", modifiers: [.command]),
                label: "Toggle Edit Mode",
                icon: "rectangle.split.2x2"
            ),

            // Workspace commands
            CommandDefinition(
                command: .toggleSidebar,
                keyBinding: KeyBinding(key: "s", modifiers: [.command, .shift]),
                label: "Toggle Sidebar",
                icon: "sidebar.left"
            ),
            CommandDefinition(
                command: .newFloatingTerminal,
                label: "New Floating Terminal",
                icon: "terminal.fill"
            ),

            // Webview commands
            CommandDefinition(
                command: .openWebview,
                label: "Open New Webview Tab",
                icon: "globe"
            ),
            CommandDefinition(
                command: .signInGitHub,
                label: "Sign in to GitHub",
                icon: "person.badge.key"
            ),
            CommandDefinition(
                command: .signInGoogle,
                label: "Sign in to Google",
                icon: "person.badge.key"
            ),

            // Sidebar commands
            CommandDefinition(
                command: .filterSidebar,
                keyBinding: KeyBinding(key: "f", modifiers: [.command, .shift]),
                label: "Filter Sidebar",
                icon: "magnifyingglass"
            ),
            CommandDefinition(
                command: .openNewTerminalInTab,
                label: "Open New Terminal in Tab",
                icon: "terminal.fill",
                appliesTo: [.worktree]
            ),

            // Window commands
            CommandDefinition(
                command: .newWindow,
                keyBinding: KeyBinding(key: "n", modifiers: [.command]),
                label: "New Window",
                icon: "macwindow.badge.plus"
            ),
            CommandDefinition(
                command: .newTab,
                keyBinding: KeyBinding(key: "t", modifiers: [.command]),
                label: "New Tab",
                icon: "plus.square"
            ),
            CommandDefinition(
                command: .undoCloseTab,
                keyBinding: KeyBinding(key: "t", modifiers: [.command, .shift]),
                label: "Undo Close Tab",
                icon: "arrow.uturn.backward"
            ),
            CommandDefinition(
                command: .closeWindow,
                keyBinding: KeyBinding(key: "W", modifiers: [.command, .shift]),
                label: "Close Window",
                icon: "xmark.rectangle"
            ),

            // Tab selection commands (⌘1 through ⌘9)
            CommandDefinition(
                command: .selectTab1, keyBinding: KeyBinding(key: "1", modifiers: [.command]), label: "Select Tab 1"),
            CommandDefinition(
                command: .selectTab2, keyBinding: KeyBinding(key: "2", modifiers: [.command]), label: "Select Tab 2"),
            CommandDefinition(
                command: .selectTab3, keyBinding: KeyBinding(key: "3", modifiers: [.command]), label: "Select Tab 3"),
            CommandDefinition(
                command: .selectTab4, keyBinding: KeyBinding(key: "4", modifiers: [.command]), label: "Select Tab 4"),
            CommandDefinition(
                command: .selectTab5, keyBinding: KeyBinding(key: "5", modifiers: [.command]), label: "Select Tab 5"),
            CommandDefinition(
                command: .selectTab6, keyBinding: KeyBinding(key: "6", modifiers: [.command]), label: "Select Tab 6"),
            CommandDefinition(
                command: .selectTab7, keyBinding: KeyBinding(key: "7", modifiers: [.command]), label: "Select Tab 7"),
            CommandDefinition(
                command: .selectTab8, keyBinding: KeyBinding(key: "8", modifiers: [.command]), label: "Select Tab 8"),
            CommandDefinition(
                command: .selectTab9, keyBinding: KeyBinding(key: "9", modifiers: [.command]), label: "Select Tab 9"),
        ]

        for def in defs {
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
}
