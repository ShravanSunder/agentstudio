import Foundation
import SwiftUI

// MARK: - CommandBarScope

/// Scope of the command bar, determined by prefix character in the search input.
enum CommandBarScope {
    case everything  // no prefix — shows recents, tabs, panes, commands, worktrees
    case commands  // ">" prefix — shows only commands grouped by category
    case panes  // "@" prefix — shows only panes grouped by tab
    case repos  // "#" prefix — shows repos and worktrees for opening
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
struct CommandBarLevel: Identifiable {
    let id: String
    let title: String
    let parentLabel: String?
    let items: [CommandBarItem]

    init(id: String, title: String, parentLabel: String? = nil, items: [CommandBarItem]) {
        self.id = id
        self.title = title
        self.parentLabel = parentLabel
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
