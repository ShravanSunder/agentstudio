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

    /// Full raw text including any visible prefix characters (e.g., "> close", "$ main").
    var rawInput: String = "" {
        didSet {
            if let normalizedPrefix = Self.normalizedLeadingPrefix(for: rawInput, previousInput: oldValue),
                rawInput != normalizedPrefix
            {
                rawInput = normalizedPrefix
                return
            }
            selectedIndex = 0
        }
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

    /// Active prefix token: "> ", "$ ", "# ", or nil.
    var activePrefix: String? {
        guard navigationStack.isEmpty else { return nil }
        guard rawInput.count >= 2 else { return nil }
        let twoChars = String(rawInput.prefix(2))
        return ["> ", "$ ", "# "].contains(twoChars) ? twoChars : nil
    }

    /// Search query text after stripping the active prefix token.
    var searchQuery: String {
        guard let prefix = activePrefix else { return rawInput }
        return String(rawInput.dropFirst(prefix.count))
    }

    /// Current scope derived from prefix.
    var activeScope: CommandBarScope {
        switch activePrefix {
        case "> ": return .commands
        case "$ ": return .panes
        case "# ": return .repos
        default: return .everything
        }
    }

    var hasPrefixInText: Bool {
        activePrefix != nil && !rawInput.isEmpty
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
        case .panes: return "Search panes..."
        case .repos: return "Open repo or worktree..."
        }
    }

    /// Icon name for the scope indicator left of the search field.
    var scopeIcon: String {
        if isNested { return "magnifyingglass" }
        switch activeScope {
        case .everything: return "magnifyingglass"
        case .commands: return "chevron.right.2"
        case .panes: return "terminal"
        case .repos: return "octicon-repo"
        }
    }

    var scopeIconIsOcticon: Bool {
        scopeIcon.hasPrefix("octicon-")
    }

    // MARK: - Actions

    /// Show the command bar with an optional prefix pre-filled.
    /// Adds a trailing space after known prefixes so the cursor lands after it.
    func show(prefix: String? = nil) {
        if let prefix, !prefix.isEmpty, [">", "$", "#"].contains(prefix) {
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

    private static func normalizedLeadingPrefix(for input: String, previousInput: String) -> String? {
        guard previousInput.isEmpty else { return nil }
        guard [">", "$", "#"].contains(input) else { return nil }
        return input + " "
    }

    func loadRecents() {
        recentItemIds = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
    }

    private func persistRecents() {
        UserDefaults.standard.set(recentItemIds, forKey: Self.recentsKey)
    }
}
