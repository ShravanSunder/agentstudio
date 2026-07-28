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
    enum OpenMode: Equatable {
        case prefix(String)
        case defaultScope(CommandBarScope)
    }

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
            if isNested {
                selectedIndex = 0
            }
        }
    }

    // MARK: - Navigation

    /// Stack of nested levels. Empty = at root level.
    var navigationStack: [CommandBarLevel] = []

    /// Root scope that remains stable while navigating nested levels.
    private(set) var pinnedScope: CommandBarScope = .everything
    private(set) var defaultRootScope: CommandBarScope = .everything
    private(set) var rootSessionGeneration: Int = 0

    // MARK: - Selection

    /// Currently highlighted row index within filtered results.
    var selectedIndex: Int = 0

    // MARK: - Recents

    /// Persisted recent item IDs, ordered most-recent-first.
    var recentItemIds: [String] = []
    /// Persisted typed command history, ordered most-recent-first.
    private(set) var recentCommands: [AppCommand] = []

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

    var normalizedRootQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasMeaningfulRootQuery: Bool {
        !normalizedRootQuery.isEmpty
    }

    /// Current scope derived from prefix.
    var activeScope: CommandBarScope {
        switch activePrefix {
        case "> ": return .commands
        case "$ ": return .panes
        case "# ": return .repos
        default: return defaultRootScope
        }
    }

    var currentScope: CommandBarScope {
        isNested ? pinnedScope : activeScope
    }

    var hasPrefixInText: Bool {
        activePrefix != nil && !rawInput.isEmpty
    }

    /// Whether we're in a nested navigation level.
    var isNested: Bool { !navigationStack.isEmpty }

    /// Current level for display (last in stack, or nil for root).
    var currentLevel: CommandBarLevel? { navigationStack.last }

    var rootScopeLabel: String {
        switch currentScope {
        case .everything: return "Main"
        case .quickOpen: return "Quick Open"
        case .commands: return "Commands"
        case .panes: return "Panes"
        case .repos: return "Repositories"
        case .inbox: return "Inbox"
        }
    }

    var breadcrumbLabels: [String] {
        breadcrumbItems.map(\.accessibilityLabel)
    }

    var breadcrumbItems: [CommandBarBreadcrumbItem] {
        [
            CommandBarBreadcrumbItem(
                label: rootScopeLabel,
                accessibilityLabel: rootScopeLabel,
                icon: nil
            )
        ]
            + navigationStack.map { level in
                let accessibilityLabel = typedBreadcrumbLabel(for: level)
                return CommandBarBreadcrumbItem(
                    label: level.breadcrumbIcon == nil ? accessibilityLabel : level.title,
                    accessibilityLabel: accessibilityLabel,
                    icon: level.breadcrumbIcon
                )
            }
    }

    var breadcrumbLabel: String {
        breadcrumbLabels.joined(separator: " › ")
    }

    private func typedBreadcrumbLabel(for level: CommandBarLevel) -> String {
        guard let scopeLabel = level.scopeLabel, scopeLabel != level.title else {
            return level.title
        }
        return "\(scopeLabel) \(level.title)"
    }

    // MARK: - Placeholder

    /// Placeholder text for the search field, varies by scope.
    var placeholder: String {
        if isNested {
            return "Filter..."
        }
        switch activeScope {
        case .everything: return "Search or jump to..."
        case .quickOpen: return "Open a location..."
        case .commands: return "Run a command..."
        case .panes: return "Search panes..."
        case .repos: return "Open repo or worktree..."
        case .inbox: return "Search inbox..."
        }
    }

    /// Icon name for the scope indicator left of the search field.
    var scopeIcon: String {
        if isNested { return "magnifyingglass" }
        switch activeScope {
        case .everything: return "magnifyingglass"
        case .quickOpen: return "terminal"
        case .commands: return "chevron.right.2"
        case .panes: return "terminal"
        case .repos: return "octicon-repo"
        case .inbox: return "bell"
        }
    }

    var scopeIconIsOcticon: Bool {
        scopeIcon.hasPrefix("octicon-")
    }

    // MARK: - Actions

    /// Show the command bar rooted at a specific scope.
    func show(defaultScope: CommandBarScope = .everything) {
        show(mode: .defaultScope(defaultScope))
    }

    /// Show the command bar with a prefix pre-filled.
    func show(prefix: String) {
        show(mode: .prefix(prefix))
    }

    private func show(mode: OpenMode) {
        rootSessionGeneration += 1

        let prefix: String?
        switch mode {
        case .prefix(let requestedPrefix):
            prefix = requestedPrefix
            defaultRootScope = .everything
        case .defaultScope(let scope):
            prefix = nil
            defaultRootScope = scope
        }

        if let prefix, !prefix.isEmpty, [">", "$", "#"].contains(prefix) {
            rawInput = prefix + " "
        } else {
            rawInput = prefix ?? ""
        }
        pinnedScope = activeScope
        navigationStack = []
        selectedIndex = 0
        isVisible = true
        stateLogger.debug("Command bar shown with prefix: \(prefix ?? "(none)")")
    }

    /// Dismiss the command bar entirely.
    func dismiss() {
        rootSessionGeneration += 1
        isVisible = false
        rawInput = ""
        pinnedScope = .everything
        defaultRootScope = .everything
        navigationStack = []
        selectedIndex = 0
        stateLogger.debug("Command bar dismissed")
    }

    /// Switch prefix in-place (when already open, pressing a different shortcut).
    func switchPrefix(_ prefix: String) {
        rootSessionGeneration += 1
        navigationStack = []
        defaultRootScope = .everything
        rawInput = prefix.isEmpty ? "" : prefix + " "
        pinnedScope = activeScope
        selectedIndex = 0
    }

    @MainActor
    static func forOpen(
        windowLifecycle: WindowLifecycleAtom,
        managementLayer: ManagementLayerAtom,
        uiState: WorkspaceSidebarState
    ) -> CommandBarState {
        let state = CommandBarState()
        let owner = KeyboardOwner.current(
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer,
            uiState: uiState
        )
        state.show(defaultScope: defaultScope(for: owner))
        return state
    }

    /// Root-scope mapping is shared by the production AppDelegate open path and
    /// the test fixture entry point above so new owner→scope rows stay in sync.
    static func defaultScope(for owner: KeyboardOwner) -> CommandBarScope {
        owner == .sidebar(.inbox) ? .inbox : .everything
    }

    /// Push a nested level onto the navigation stack.
    func pushLevel(_ level: CommandBarLevel) {
        navigationStack.append(level)
        rawInput = ""
        selectedIndex = 0
    }

    /// Pop the current nested level while preserving its parent.
    func popLevel() {
        guard !navigationStack.isEmpty else { return }
        navigationStack.removeLast()
        rawInput = ""
        selectedIndex = 0
    }

    /// Navigate directly to an ancestor represented by a breadcrumb index.
    func navigateToBreadcrumb(at index: Int) {
        guard index >= 0, index < breadcrumbLabels.count - 1 else { return }
        navigationStack = Array(navigationStack.prefix(index))
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
        if recentItemIds.count > AppPolicies.CommandBar.maximumHistoryCount {
            recentItemIds = Array(recentItemIds.prefix(AppPolicies.CommandBar.maximumHistoryCount))
        }
        persistRecents()
    }

    func recordRecentCommand(_ command: AppCommand) {
        recentCommands.removeAll { $0 == command }
        recentCommands.insert(command, at: 0)
        if recentCommands.count > AppPolicies.CommandBar.maximumHistoryCount {
            recentCommands = Array(recentCommands.prefix(AppPolicies.CommandBar.maximumHistoryCount))
        }
        persistRecentCommands()
    }

    // MARK: - Persistence

    private static let recentsKey = "CommandBarRecentItemIds"
    private static let recentCommandsKey = "CommandBarRecentCommands"

    private static func normalizedLeadingPrefix(for input: String, previousInput: String) -> String? {
        guard previousInput.isEmpty else { return nil }
        guard [">", "$", "#"].contains(input) else { return nil }
        return input + " "
    }

    func loadRecents() {
        recentItemIds = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
        let storedCommandValues = UserDefaults.standard.stringArray(forKey: Self.recentCommandsKey) ?? []
        var seenCommands: Set<AppCommand> = []
        recentCommands =
            storedCommandValues
            .compactMap(AppCommand.init(rawValue:))
            .filter { seenCommands.insert($0).inserted }
            .prefix(AppPolicies.CommandBar.maximumHistoryCount)
            .map(\.self)
    }

    private func persistRecents() {
        UserDefaults.standard.set(recentItemIds, forKey: Self.recentsKey)
    }

    private func persistRecentCommands() {
        UserDefaults.standard.set(recentCommands.map(\.rawValue), forKey: Self.recentCommandsKey)
    }
}
