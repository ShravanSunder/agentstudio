import AgentStudioCore
import AgentStudioSharedComponents
import SwiftUI

// MARK: - CommandBarAppMode

/// Global app mode displayed in the command bar status strip.
enum CommandBarAppMode {
    case normal
    case management

    var statusStripLabel: String? {
        switch self {
        case .normal:
            return nil
        case .management:
            return "Management"
        }
    }

    var statusStripIcon: String? {
        switch self {
        case .normal:
            return nil
        case .management:
            return "rectangle.split.2x2.fill"
        }
    }
}

// MARK: - EnterModifier

package enum EnterModifier: Sendable {
    case plain
    case command
    case option
}

package enum CommandBarRecentActivation: Equatable, Sendable {
    case repository(repositoryStableKey: String)
    case worktree(worktreeStableKey: String)
    case pane(paneID: UUID, workspaceID: UUID)
}

package enum CommandBarQuickOpenTarget: Equatable, Sendable {
    case repository(repositoryStableKey: String)
    case worktree(worktreeStableKey: String)
    case directory(URL)
}

package enum QuickOpenDirectoryPlacement: Equatable, Sendable {
    case currentTabPane
    case newTab
}

// MARK: - CommandBarAction

/// What happens when a command bar item is selected.
package enum CommandBarAction {
    /// Execute a contextual command (operates on active element)
    case dispatch(AppCommand)
    /// Execute a targeted command (operates on a specific element)
    case dispatchTargeted(AppCommand, target: UUID, targetType: SearchItemType)
    /// Drill into a sub-level (nested navigation)
    case navigate(CommandBarLevel)
    /// Resolve and drill into a repository sub-level only when the row is accepted.
    case navigateRepo(repositoryID: UUID)
    /// Arbitrary action (e.g., open URL, show dialog)
    case custom(@Sendable () -> Void)
    /// Resolve worktree behavior at selection time based on presence and modifier keys.
    case worktreeAction(presence: WorktreePresence)
    /// Open a terminal at a live repository/worktree target or enter its existing actions.
    case quickOpen(CommandBarQuickOpenTarget)
    /// Re-resolve a typed recent entity against live state immediately before dispatch.
    case activateRecent(CommandBarRecentActivation)
}

package enum CommandBarItemKind {
    case repo
    case tab
    case pane
    case worktree
    case command
    case other
}

package struct CommandBarItemSecondaryLine: Equatable, Sendable {
    package let text: String
    package let icon: CommandIcon?
}

// MARK: - CommandBarItem

/// A single result row in the command bar.
package struct CommandBarItem: Identifiable {
    package let id: String
    package let title: String
    package let subtitle: String?
    package let secondaryLine: CommandBarItemSecondaryLine?
    package let icon: CommandIcon?
    package let iconColor: Color?
    package let shortcutTrigger: ShortcutTrigger?
    package let shortcutKeys: [ShortcutKey]?
    package let group: String
    package let groupPriority: Int
    package let keywords: [String]
    package let hasChildren: Bool
    package let showsActionsButton: Bool
    package let action: CommandBarAction
    /// The underlying command, if any. Used for dimming navigate items whose command is unavailable.
    package let command: AppCommand?
    package let accessibilityLabel: String
    package let accessibilityHint: String

    package init(
        id: String,
        title: String,
        subtitle: String? = nil,
        secondaryLine: CommandBarItemSecondaryLine? = nil,
        icon: CommandIcon? = nil,
        iconColor: Color? = nil,
        shortcutTrigger: ShortcutTrigger? = nil,
        shortcutKeys: [ShortcutKey]? = nil,
        group: String,
        groupPriority: Int,
        keywords: [String] = [],
        hasChildren: Bool = false,
        showsActionsButton: Bool = false,
        action: CommandBarAction,
        command: AppCommand? = nil,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.secondaryLine = secondaryLine
        self.icon = icon
        self.iconColor = iconColor
        self.shortcutTrigger = shortcutTrigger
        self.shortcutKeys = shortcutKeys ?? shortcutTrigger.map(Self.shortcutKeys(for:))
        self.group = group
        self.groupPriority = groupPriority
        self.keywords = keywords
        self.hasChildren = hasChildren
        self.showsActionsButton = showsActionsButton
        self.action = action
        self.command = command
        self.accessibilityLabel =
            accessibilityLabel
            ?? [title, subtitle, secondaryLine?.text].compactMap(\.self).joined(separator: ", ")
        self.accessibilityHint =
            accessibilityHint
            ?? Self.defaultAccessibilityHint(
                title: title,
                action: action
            )
    }

    private static func shortcutKeys(for trigger: ShortcutTrigger) -> [ShortcutKey] {
        ShortcutKey.from(trigger: trigger)
    }

    private static func defaultAccessibilityHint(
        title: String,
        action: CommandBarAction
    ) -> String {
        switch action {
        case .dispatch:
            return "Run \(title)"
        case .dispatchTargeted(let command, _, _):
            return command == .focusPane ? "Focus pane" : "Run \(title)"
        case .navigate, .navigateRepo:
            return "Show \(title) actions"
        case .custom:
            return title
        case .worktreeAction:
            return "Show worktree actions"
        case .quickOpen:
            return "Open terminal"
        case .activateRecent(let activation):
            switch activation {
            case .repository: return "Show repository actions"
            case .worktree: return "Show worktree actions"
            case .pane: return "Focus pane"
            }
        }
    }

    func projected(
        group: String,
        groupPriority: Int,
        action: CommandBarAction? = nil,
        hasChildren: Bool? = nil,
        showsActionsButton: Bool? = nil,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil
    ) -> Self {
        Self(
            id: id,
            title: title,
            subtitle: subtitle,
            secondaryLine: secondaryLine,
            icon: icon,
            iconColor: iconColor,
            shortcutTrigger: shortcutTrigger,
            shortcutKeys: shortcutKeys,
            group: group,
            groupPriority: groupPriority,
            keywords: keywords,
            hasChildren: hasChildren ?? self.hasChildren,
            showsActionsButton: showsActionsButton ?? self.showsActionsButton,
            action: action ?? self.action,
            command: command,
            accessibilityLabel: accessibilityLabel ?? self.accessibilityLabel,
            accessibilityHint: accessibilityHint ?? self.accessibilityHint
        )
    }

    var worktreeOpenState: WorktreeOpenState? {
        switch action {
        case .worktreeAction(let presence):
            return presence.openState
        case .dispatch, .dispatchTargeted, .navigate, .navigateRepo, .custom, .quickOpen, .activateRecent:
            return nil
        }
    }

    var kind: CommandBarItemKind {
        switch action {
        case .worktreeAction:
            return .worktree
        case .quickOpen(let target):
            switch target {
            case .repository: return .repo
            case .worktree: return .worktree
            case .directory: return .other
            }
        case .dispatch:
            return .command
        case .navigate:
            return command == nil ? .other : .command
        case .navigateRepo:
            return .repo
        case .custom:
            return .other
        case .activateRecent(let activation):
            switch activation {
            case .repository: return .repo
            case .worktree: return .worktree
            case .pane: return .pane
            }
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
package struct ShortcutKey: Identifiable, Hashable {
    package let id = UUID()
    package let symbol: String

    package init(symbol: String) {
        self.symbol = symbol
    }

    static func from(keyBinding: KeyBinding) -> [Self] {
        var keys: [Self] = []
        if keyBinding.modifiers.contains(.command) { keys.append(Self(symbol: "⌘")) }
        if keyBinding.modifiers.contains(.shift) { keys.append(Self(symbol: "⇧")) }
        if keyBinding.modifiers.contains(.option) { keys.append(Self(symbol: "⌥")) }
        if keyBinding.modifiers.contains(.control) { keys.append(Self(symbol: "⌃")) }
        keys.append(Self(symbol: keyBinding.key.uppercased()))
        return keys
    }

    static func from(trigger: ShortcutTrigger) -> [Self] {
        var keys: [Self] = []
        if trigger.modifiers.contains(.command) { keys.append(Self(symbol: "⌘")) }
        if trigger.modifiers.contains(.shift) { keys.append(Self(symbol: "⇧")) }
        if trigger.modifiers.contains(.option) { keys.append(Self(symbol: "⌥")) }
        if trigger.modifiers.contains(.control) { keys.append(Self(symbol: "⌃")) }
        keys.append(Self(symbol: trigger.key.displayString))
        return keys
    }
}

// MARK: - CommandBarLevel

struct CommandBarBreadcrumbItem: Equatable {
    let label: String
    let accessibilityLabel: String
    let icon: AppEntityIcon?
}

/// A navigation level in the command bar (for nested drill-in).
///
/// `scopeLabel` identifies the level's entity or action kind in the breadcrumb.
package struct CommandBarLevel: Identifiable {
    package let id: String
    package let title: String
    package let parentLabel: String?
    package let scopeLabel: String?
    package let breadcrumbIcon: AppEntityIcon?
    package let items: [CommandBarItem]

    package init(
        id: String,
        title: String,
        parentLabel: String? = nil,
        scopeLabel: String? = nil,
        breadcrumbIcon: AppEntityIcon? = nil,
        items: [CommandBarItem]
    ) {
        self.id = id
        self.title = title
        self.parentLabel = parentLabel
        self.scopeLabel = scopeLabel
        self.breadcrumbIcon = breadcrumbIcon
        self.items = items
    }
}

// MARK: - CommandBarItemGroup

/// A grouped section of command bar items for display.
package struct CommandBarItemGroup: Identifiable {
    package let id: String
    package let name: String
    package let priority: Int
    package let items: [CommandBarItem]

    package init(id: String, name: String, priority: Int, items: [CommandBarItem]) {
        self.id = id
        self.name = name
        self.priority = priority
        self.items = items
    }
}

// MARK: - FooterHint

package enum FooterHintStyle: Equatable, Sendable {
    case badge
    case plain
}

package struct FooterHint: Identifiable, Equatable, Sendable {
    package let id: String
    package let shortcutKeys: [ShortcutKey]
    package let label: String
    package let isDivider: Bool
    package let style: FooterHintStyle

    init(
        id: String,
        key: String,
        label: String,
        isDivider: Bool = false,
        style: FooterHintStyle = .badge
    ) {
        self.id = id
        self.shortcutKeys = [ShortcutKey(symbol: key)]
        self.label = label
        self.isDivider = isDivider
        self.style = style
    }

    init(
        id: String,
        keys: [ShortcutKey],
        label: String,
        isDivider: Bool = false,
        style: FooterHintStyle = .badge
    ) {
        self.id = id
        self.shortcutKeys = keys
        self.label = label
        self.isDivider = isDivider
        self.style = style
    }

    static func divider(_ id: String) -> Self {
        Self(id: id, keys: [], label: "", isDivider: true, style: .plain)
    }
}

struct FooterHintLayout: Equatable, Sendable {
    let primaryRow: [FooterHint]
    let secondaryLeadingRow: [FooterHint]
    let secondaryTrailingRow: [FooterHint]
}

// MARK: - FooterHintBuilder

package enum FooterHintBuilder {
    package static func hints(
        for item: CommandBarItem?,
        isNested: Bool,
        canOpenInCurrentTab: Bool,
        scope: CommandBarScope = .everything
    ) -> [FooterHint] {
        if isNested {
            var hints: [FooterHint] = []
            if item?.hasChildren == true {
                hints.append(FooterHint(id: "drill-in", key: "⇥", label: "Actions"))
            }
            hints.append(.divider("div-dismiss"))
            hints.append(FooterHint(id: "back", key: "⇧⇥ / ⌫", label: "Back", style: .plain))
            hints.append(FooterHint(id: "dismiss", key: "esc", label: "Close", style: .plain))
            return hints
        }

        // Action hints — item-specific
        var actions: [FooterHint] = []

        if let item {
            if case .quickOpen = item.action {
                actions = [
                    FooterHint(id: "enter", key: "↵", label: "Open"),
                    FooterHint(
                        id: "cmd-enter",
                        keys: [ShortcutKey(symbol: "⌘"), ShortcutKey(symbol: "↵")],
                        label: "New tab"
                    ),
                ]
                if canOpenInCurrentTab {
                    actions.append(
                        FooterHint(
                            id: "opt-enter",
                            keys: [ShortcutKey(symbol: "⌥"), ShortcutKey(symbol: "↵")],
                            label: "Open in tab"
                        )
                    )
                }
                if item.showsActionsButton {
                    actions.append(FooterHint(id: "drill-in", key: "⇥", label: "Actions"))
                }
            } else if item.worktreeOpenState != nil {
                actions = [
                    FooterHint(
                        id: "cmd-enter",
                        keys: [ShortcutKey(symbol: "⌘"), ShortcutKey(symbol: "↵")],
                        label: "New tab"
                    )
                ]
                if canOpenInCurrentTab {
                    actions.append(
                        FooterHint(
                            id: "opt-enter",
                            keys: [ShortcutKey(symbol: "⌥"), ShortcutKey(symbol: "↵")],
                            label: "Open in tab"
                        )
                    )
                }
            } else {
                let enterLabel = (item.kind == .tab || item.kind == .pane) ? "Go to" : "Open"
                actions = [FooterHint(id: "enter", key: "↵", label: enterLabel)]
                if item.hasChildren {
                    actions.append(FooterHint(id: "drill-in", key: "→", label: "Drill in"))
                }
                if let shortcutKeys = item.shortcutKeys {
                    actions.append(
                        FooterHint(
                            id: "item-shortcut",
                            keys: shortcutKeys,
                            label: "Shortcut"
                        )
                    )
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
        hints.append(FooterHint(id: "dismiss", key: "esc", label: "Close", style: .plain))
        return hints
    }

    static func layout(for hints: [FooterHint]) -> FooterHintLayout {
        var primaryRow: [FooterHint] = []
        var secondaryLeadingRow: [FooterHint] = []
        var secondaryTrailingRow: [FooterHint] = []

        for hint in hints where !hint.isDivider {
            switch hint.id {
            case "dismiss":
                secondaryTrailingRow.append(hint)
            case "scope-commands", "scope-panes", "scope-repos", "back":
                secondaryLeadingRow.append(hint)
            default:
                primaryRow.append(hint)
            }
        }

        return FooterHintLayout(
            primaryRow: primaryRow,
            secondaryLeadingRow: secondaryLeadingRow,
            secondaryTrailingRow: secondaryTrailingRow
        )
    }

    private static let scopeHints: [FooterHint] = [
        FooterHint(id: "scope-commands", key: ">", label: "cmd", style: .plain),
        FooterHint(id: "scope-panes", key: "$", label: "pane", style: .plain),
        FooterHint(id: "scope-repos", key: "#", label: "repo", style: .plain),
    ]
}
