import SwiftUI

// MARK: - CommandBarScope

/// Scope of the command bar, determined by prefix character in the search input.
enum CommandBarScope {
    case everything  // no prefix — shows recents, tabs, panes, commands, worktrees
    case commands  // ">" prefix — shows only commands grouped by category
    case panes  // "$" prefix — shows only panes grouped by tab
    case repos  // "#" prefix — shows repos and worktrees for opening
}

// MARK: - CommandBarAppMode

/// Global app mode displayed in the command bar status strip.
enum CommandBarAppMode {
    case normal
    case management

    var label: String {
        switch self {
        case .normal:
            return "Normal"
        case .management:
            return "Manage"
        }
    }

    var icon: String {
        switch self {
        case .normal:
            return "rectangle.split.2x2"
        case .management:
            return "rectangle.split.2x2.fill"
        }
    }

    var isAccented: Bool {
        switch self {
        case .normal:
            return false
        case .management:
            return true
        }
    }
}

// MARK: - EnterModifier

enum EnterModifier: Sendable {
    case plain
    case command
    case option
}

// MARK: - CommandBarAction

/// What happens when a command bar item is selected.
enum CommandBarAction {
    /// Execute a contextual command (operates on active element)
    case dispatch(AppCommand)
    /// Execute a targeted command (operates on a specific element)
    case dispatchTargeted(AppCommand, target: UUID, targetType: SearchItemType)
    /// Drill into a sub-level (nested navigation)
    case navigate(CommandBarLevel)
    /// Arbitrary action (e.g., open URL, show dialog)
    case custom(@Sendable () -> Void)
    /// Resolve worktree behavior at selection time based on presence and modifier keys.
    case worktreeAction(presence: WorktreePresence)
}

enum CommandBarItemKind {
    case tab
    case pane
    case worktree
    case command
    case other
}

// MARK: - CommandBarItem

/// A single result row in the command bar.
struct CommandBarItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String?
    let iconColor: Color?
    let shortcutKeys: [ShortcutKey]?
    let group: String
    let groupPriority: Int
    let keywords: [String]
    let hasChildren: Bool
    let action: CommandBarAction
    /// The underlying command, if any. Used for dimming navigate items whose command is unavailable.
    let command: AppCommand?

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        iconColor: Color? = nil,
        shortcutKeys: [ShortcutKey]? = nil,
        group: String,
        groupPriority: Int,
        keywords: [String] = [],
        hasChildren: Bool = false,
        action: CommandBarAction,
        command: AppCommand? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self.shortcutKeys = shortcutKeys
        self.group = group
        self.groupPriority = groupPriority
        self.keywords = keywords
        self.hasChildren = hasChildren
        self.action = action
        self.command = command
    }

    var worktreeOpenState: WorktreeOpenState? {
        switch action {
        case .worktreeAction(let presence):
            return presence.openState
        case .dispatch, .dispatchTargeted, .navigate, .custom:
            return nil
        }
    }

    var kind: CommandBarItemKind {
        switch action {
        case .worktreeAction:
            return .worktree
        case .dispatch:
            return .command
        case .navigate:
            return command == nil ? .other : .command
        case .custom:
            return .other
        case .dispatchTargeted(let command, _, let targetType):
            if command == .selectTab && targetType == .tab {
                return .tab
            }
            if command == .focusPane && (targetType == .pane || targetType == .floatingTerminal) {
                return .pane
            }
            return .command
        }
    }
}

// MARK: - ShortcutKey

/// A single key in a keyboard shortcut badge (e.g., "⌘", "W").
struct ShortcutKey: Identifiable, Hashable {
    let id = UUID()
    let symbol: String

    static func from(keyBinding: KeyBinding) -> [Self] {
        var keys: [Self] = []
        if keyBinding.modifiers.contains(.command) { keys.append(Self(symbol: "⌘")) }
        if keyBinding.modifiers.contains(.shift) { keys.append(Self(symbol: "⇧")) }
        if keyBinding.modifiers.contains(.option) { keys.append(Self(symbol: "⌥")) }
        if keyBinding.modifiers.contains(.control) { keys.append(Self(symbol: "⌃")) }
        keys.append(Self(symbol: keyBinding.key.uppercased()))
        return keys
    }
}

// MARK: - CommandBarLevel

/// A navigation level in the command bar (for nested drill-in).
///
/// When `scopeLabel` is set, the pill shows the scope label (e.g. "Worktrees · Actions")
/// and the back row shows `‹ {title}`. When `scopeLabel` is nil, the pill shows `title`
/// and the back row shows a bare `‹`.
struct CommandBarLevel: Identifiable {
    let id: String
    let title: String
    let parentLabel: String?
    let scopeLabel: String?
    let items: [CommandBarItem]

    init(
        id: String,
        title: String,
        parentLabel: String? = nil,
        scopeLabel: String? = nil,
        items: [CommandBarItem]
    ) {
        self.id = id
        self.title = title
        self.parentLabel = parentLabel
        self.scopeLabel = scopeLabel
        self.items = items
    }
}

// MARK: - CommandBarItemGroup

/// A grouped section of command bar items for display.
struct CommandBarItemGroup: Identifiable {
    let id: String
    let name: String
    let priority: Int
    let items: [CommandBarItem]
}

// MARK: - FooterHint

struct FooterHint: Identifiable, Equatable, Sendable {
    let id: String
    let key: String
    let label: String
    let isDivider: Bool

    init(id: String, key: String, label: String, isDivider: Bool = false) {
        self.id = id
        self.key = key
        self.label = label
        self.isDivider = isDivider
    }

    static func divider(_ id: String) -> Self {
        Self(id: id, key: "", label: "", isDivider: true)
    }
}

// MARK: - FooterHintBuilder

enum FooterHintBuilder {
    static func hints(
        for item: CommandBarItem?,
        isNested: Bool,
        canOpenInCurrentTab: Bool,
        scope: CommandBarScope = .everything
    ) -> [FooterHint] {
        if isNested {
            return [
                FooterHint(id: "enter", key: "↵", label: "Select"),
                FooterHint(id: "back", key: "⌫", label: "Back"),
                .divider("div-dismiss"),
                FooterHint(id: "dismiss", key: "esc", label: "Close"),
            ]
        }

        // Action hints — item-specific
        var actions: [FooterHint] = []

        if let item {
            if item.worktreeOpenState != nil {
                actions = [
                    FooterHint(id: "enter", key: "↵", label: "Actions"),
                    FooterHint(id: "cmd-enter", key: "⌘↵", label: "New tab"),
                ]
                if canOpenInCurrentTab {
                    actions.append(FooterHint(id: "opt-enter", key: "⌥↵", label: "Open in tab"))
                }
            } else {
                let enterLabel = (item.kind == .tab || item.kind == .pane) ? "Go to" : "Open"
                actions = [FooterHint(id: "enter", key: "↵", label: enterLabel)]
                if item.hasChildren {
                    actions.append(FooterHint(id: "drill-in", key: "→", label: "Drill in"))
                }
            }
        }

        // Assemble: actions | scopes | dismiss
        var hints = actions
        if scope == .everything {
            if !hints.isEmpty { hints.append(.divider("div-scope")) }
            hints.append(contentsOf: scopeHints)
        }
        hints.append(.divider("div-dismiss"))
        hints.append(FooterHint(id: "dismiss", key: "esc", label: "Close"))
        return hints
    }

    private static let scopeHints: [FooterHint] = [
        FooterHint(id: "scope-commands", key: ">", label: "Commands"),
        FooterHint(id: "scope-panes", key: "$", label: "Panes"),
        FooterHint(id: "scope-repos", key: "#", label: "Repos"),
    ]
}
