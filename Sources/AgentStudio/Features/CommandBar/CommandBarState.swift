import Foundation
import SwiftUI
import os.log

private let stateLogger = Logger(subsystem: "com.agentstudio", category: "CommandBarState")

// MARK: - CommandBarState

/// Observable state for the command bar.
/// Manages visibility, search input with prefix parsing, navigation stack, and selection.
/// Always accessed on the main thread (SwiftUI views + AppKit panel controller).
@Observable
final class CommandBarState {
    // MARK: - Visibility

    var isVisible: Bool = false

    // MARK: - Search Input

    /// Full raw text including prefix character (e.g., ">close", "@main").
    var rawInput: String = "" {
        didSet { selectedIndex = 0 }
    }

    // MARK: - Navigation

    /// Stack of nested levels. Empty = at root level.
    var navigationStack: [CommandBarLevel] = []

    // MARK: - Selection

    /// Currently highlighted row index within filtered results.
    var selectedIndex: Int = 0

    // MARK: - Recents

    /// Persisted recent item IDs, ordered most-recent-first.
    var recentItemIds: [String] = []

    // MARK: - Computed — Prefix Parsing

    /// Active prefix character: ">", "@", or nil.
    var activePrefix: String? {
        guard navigationStack.isEmpty else { return nil }
        guard let first = rawInput.first else { return nil }
        let char = String(first)
        return [">", "@", "#"].contains(char) ? char : nil
    }

    /// Search query text after stripping the prefix (and any leading space).
    var searchQuery: String {
        guard let prefix = activePrefix else { return rawInput }
        let afterPrefix = String(rawInput.dropFirst(prefix.count))
        // Strip the space we insert after the prefix for cursor positioning
        if afterPrefix.first == " " {
            return String(afterPrefix.dropFirst())
        }
        return afterPrefix
    }

    /// Current scope derived from prefix.
    var activeScope: CommandBarScope {
        switch activePrefix {
        case ">": return .commands
        case "@": return .panes
        case "#": return .repos
        default: return .everything
        }
    }

    /// Whether we're in a nested navigation level.
    var isNested: Bool { !navigationStack.isEmpty }

    /// Current level for display (last in stack, or nil for root).
    var currentLevel: CommandBarLevel? { navigationStack.last }

    /// Scope pill text components (only when nested).
    var scopePillParent: String? { currentLevel?.parentLabel }
    var scopePillChild: String? { currentLevel?.title }

    // MARK: - Placeholder

    /// Placeholder text for the search field, varies by scope.
    var placeholder: String {
        if isNested {
            return "Filter..."
        }
        switch activeScope {
        case .everything: return "Search or jump to..."
        case .commands: return "Run a command..."
        case .panes: return "Switch to pane..."
        case .repos: return "Open repo or worktree..."
        }
    }

    /// SF Symbol name for the scope icon left of the search field.
    var scopeIcon: String {
        if isNested { return "magnifyingglass" }
        switch activeScope {
        case .everything: return "magnifyingglass"
        case .commands: return "chevron.right.2"
        case .panes: return "at"
        case .repos: return "number"
        }
    }

    // MARK: - Actions

    /// Show the command bar with an optional prefix pre-filled.
    /// Adds a trailing space after known prefixes so the cursor lands after it.
    func show(prefix: String? = nil) {
        if let prefix, !prefix.isEmpty, [">", "@", "#"].contains(prefix) {
            rawInput = prefix + " "
        } else {
            rawInput = prefix ?? ""
        }
        navigationStack = []
        selectedIndex = 0
        isVisible = true
        stateLogger.debug("Command bar shown with prefix: \(prefix ?? "(none)")")
    }

    /// Dismiss the command bar entirely.
    func dismiss() {
        isVisible = false
        rawInput = ""
        navigationStack = []
        selectedIndex = 0
        stateLogger.debug("Command bar dismissed")
    }

    /// Switch prefix in-place (when already open, pressing a different shortcut).
    func switchPrefix(_ prefix: String) {
        navigationStack = []
        rawInput = prefix.isEmpty ? "" : prefix + " "
        selectedIndex = 0
    }

    /// Push a nested level onto the navigation stack.
    func pushLevel(_ level: CommandBarLevel) {
        navigationStack.append(level)
        rawInput = ""
        selectedIndex = 0
    }

    /// Pop back to root level.
    func popToRoot() {
        navigationStack = []
        rawInput = ""
        selectedIndex = 0
    }

    /// Move selection up by one row.
    func moveSelectionUp(totalItems: Int) {
        guard totalItems > 0 else { return }
        selectedIndex = selectedIndex > 0 ? selectedIndex - 1 : totalItems - 1
    }

    /// Move selection down by one row.
    func moveSelectionDown(totalItems: Int) {
        guard totalItems > 0 else { return }
        selectedIndex = selectedIndex < totalItems - 1 ? selectedIndex + 1 : 0
    }

    /// Record an item as recently used.
    func recordRecent(itemId: String) {
        recentItemIds.removeAll { $0 == itemId }
        recentItemIds.insert(itemId, at: 0)
        if recentItemIds.count > 8 {
            recentItemIds = Array(recentItemIds.prefix(8))
        }
        persistRecents()
    }

    // MARK: - Persistence

    private static let recentsKey = "CommandBarRecentItemIds"

    func loadRecents() {
        recentItemIds = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
    }

    private func persistRecents() {
        UserDefaults.standard.set(recentItemIds, forKey: Self.recentsKey)
    }
}
