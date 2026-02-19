import Foundation
import SwiftUI

// MARK: - CommandBarDataSource

/// Builds CommandBarItem arrays from WorkspaceStore and CommandDispatcher.
/// Single source of truth for all command bar content, filtered by scope.
@MainActor
enum CommandBarDataSource {

    // MARK: - Group Names & Priorities

    private enum Group {
        static let recent = "Recent"
        static let tabs = "Tabs"
        static let panes = "Panes"
        static let commands = "Commands"
        static let worktrees = "Worktrees"

        // Sub-groups for commands scope
        static let paneCommands = "Pane"
        static let focusCommands = "Focus"
        static let tabCommands = "Tab"
        static let repoCommands = "Repo"
        static let windowCommands = "Window"
        static let webviewCommands = "Webview"
        static let authCommands = "Auth"
    }

    private enum Priority {
        static let recent = 0
        static let tabs = 1
        static let panes = 2
        static let commands = 3
        static let worktrees = 4
    }

    // MARK: - Public API

    /// Build all items for the given scope from live app state.
    static func items(
        scope: CommandBarScope,
        store: WorkspaceStore,
        dispatcher: CommandDispatcher
    ) -> [CommandBarItem] {
        switch scope {
        case .everything:
            return everythingItems(store: store, dispatcher: dispatcher)
        case .commands:
            return commandItems(dispatcher: dispatcher, store: store)
        case .panes:
            return paneAndTabItems(store: store)
        }
    }

    /// Group a flat list of items into display groups, ordered by priority.
    static func grouped(_ items: [CommandBarItem]) -> [CommandBarItemGroup] {
        let dict = Dictionary(grouping: items, by: \.group)
        return dict
            .map { name, groupItems in
                let priority = groupItems.first?.groupPriority ?? 999
                return CommandBarItemGroup(
                    id: name,
                    name: name,
                    priority: priority,
                    items: groupItems
                )
            }
            .sorted { $0.priority < $1.priority }
    }

    // MARK: - Everything Scope

    private static func everythingItems(
        store: WorkspaceStore,
        dispatcher: CommandDispatcher
    ) -> [CommandBarItem] {
        var items: [CommandBarItem] = []
        items.append(contentsOf: tabItems(store: store))
        items.append(contentsOf: paneItems(store: store))
        items.append(contentsOf: allCommandItems(dispatcher: dispatcher, store: store, groupName: Group.commands, priority: Priority.commands))
        items.append(contentsOf: worktreeItems(store: store))
        return items
    }

    // MARK: - Tab Items

    private static func tabItems(store: WorkspaceStore) -> [CommandBarItem] {
        store.tabs.enumerated().map { index, tab in
            let paneTitles = tab.paneIds.compactMap { store.pane($0)?.title }
            let title = paneTitles.count > 1
                ? paneTitles.joined(separator: " | ")
                : paneTitles.first ?? "Terminal"
            let isActive = tab.id == store.activeTabId

            let tabId = tab.id
            return CommandBarItem(
                id: "tab-\(tab.id.uuidString)",
                title: title,
                subtitle: isActive ? "Active · Tab \(index + 1)" : "Tab \(index + 1)",
                icon: "rectangle.stack",
                group: Group.tabs,
                groupPriority: Priority.tabs,
                keywords: ["tab", "switch"],
                action: .custom {
                    NotificationCenter.default.post(
                        name: .selectTabById,
                        object: nil,
                        userInfo: ["tabId": tabId]
                    )
                }
            )
        }
    }

    // MARK: - Pane Items

    private static func paneItems(store: WorkspaceStore) -> [CommandBarItem] {
        var items: [CommandBarItem] = []
        for (tabIndex, tab) in store.tabs.enumerated() {
            for paneId in tab.paneIds {
                guard let pane = store.pane(paneId) else { continue }
                let isActive = tab.activePaneId == paneId

                let capturedPaneId = pane.id
                let parentTabId = tab.id
                items.append(CommandBarItem(
                    id: "pane-\(pane.id.uuidString)",
                    title: pane.title,
                    subtitle: "Tab \(tabIndex + 1)" + (isActive ? " · Active" : ""),
                    icon: iconForPane(pane),
                    iconColor: pane.agent?.color,
                    group: Group.panes,
                    groupPriority: Priority.panes,
                    keywords: keywordsForPane(pane, store: store),
                    action: .custom {
                        // Select the parent tab and focus the specific pane
                        NotificationCenter.default.post(
                            name: .selectTabById,
                            object: nil,
                            userInfo: ["tabId": parentTabId, "paneId": capturedPaneId]
                        )
                    }
                ))
            }
        }
        return items
    }

    // MARK: - Panes Scope (grouped by tab)

    private static func paneAndTabItems(store: WorkspaceStore) -> [CommandBarItem] {
        var items: [CommandBarItem] = []
        for (tabIndex, tab) in store.tabs.enumerated() {
            let paneTitles = tab.paneIds.compactMap { store.pane($0)?.title }
            let tabTitle = paneTitles.count > 1
                ? paneTitles.joined(separator: " | ")
                : paneTitles.first ?? "Terminal"
            let tabGroupName = "Tab \(tabIndex + 1): \(tabTitle)"
            let isActiveTab = tab.id == store.activeTabId

            // Tab as selectable item
            let tabId = tab.id
            items.append(CommandBarItem(
                id: "tab-\(tab.id.uuidString)",
                title: tabTitle,
                subtitle: isActiveTab ? "Active Tab" : nil,
                icon: "rectangle.stack",
                group: tabGroupName,
                groupPriority: tabIndex,
                keywords: ["tab", "switch"],
                action: .custom {
                    NotificationCenter.default.post(
                        name: .selectTabById,
                        object: nil,
                        userInfo: ["tabId": tabId]
                    )
                }
            ))

            // Panes within this tab
            for paneId in tab.paneIds {
                guard let pane = store.pane(paneId) else { continue }
                let isActive = tab.activePaneId == paneId

                let capturedTabId = tab.id
                let capturedPaneId = pane.id
                items.append(CommandBarItem(
                    id: "pane-\(pane.id.uuidString)",
                    title: pane.title,
                    subtitle: isActive ? "Active Pane" : nil,
                    icon: iconForPane(pane),
                    iconColor: pane.agent?.color,
                    group: tabGroupName,
                    groupPriority: tabIndex,
                    keywords: keywordsForPane(pane, store: store),
                    action: .custom {
                        NotificationCenter.default.post(
                            name: .selectTabById,
                            object: nil,
                            userInfo: ["tabId": capturedTabId, "paneId": capturedPaneId]
                        )
                    }
                ))
            }
        }
        return items
    }

    // MARK: - Command Items

    /// Visible command definitions, filtered once.
    private static func visibleCommands(dispatcher: CommandDispatcher) -> [CommandDefinition] {
        dispatcher.definitions.values.filter { !isHiddenCommand($0.command) }
    }

    /// Commands grouped by category (for `.commands` scope).
    private static func commandItems(dispatcher: CommandDispatcher, store: WorkspaceStore) -> [CommandBarItem] {
        visibleCommands(dispatcher: dispatcher)
            .sorted { $0.command.rawValue < $1.command.rawValue }
            .map { def in
                let (groupName, groupPriority) = commandGroup(for: def.command)
                return commandItem(from: def, groupName: groupName, groupPriority: groupPriority, store: store)
            }
    }

    /// All commands in a flat group (for `.everything` scope).
    private static func allCommandItems(
        dispatcher: CommandDispatcher,
        store: WorkspaceStore,
        groupName: String,
        priority: Int
    ) -> [CommandBarItem] {
        visibleCommands(dispatcher: dispatcher)
            .sorted { $0.label < $1.label }
            .map { commandItem(from: $0, groupName: groupName, groupPriority: priority, store: store) }
    }

    private static func commandItem(
        from def: CommandDefinition,
        groupName: String,
        groupPriority: Int,
        store: WorkspaceStore? = nil
    ) -> CommandBarItem {
        // Commands with appliesTo targets and a live store → drill-in to pick target
        let hasDrillIn = store != nil && !def.appliesTo.isEmpty && isTargetableCommand(def.command)

        if hasDrillIn, let store {
            let level = buildTargetLevel(for: def, store: store)
            return CommandBarItem(
                id: "cmd-\(def.command.rawValue)",
                title: def.label,
                icon: def.icon,
                shortcutKeys: def.keyBinding.map { ShortcutKey.from(keyBinding: $0) },
                group: groupName,
                groupPriority: groupPriority,
                keywords: commandKeywords(for: def),
                hasChildren: true,
                action: .navigate(level),
                command: def.command
            )
        }

        return CommandBarItem(
            id: "cmd-\(def.command.rawValue)",
            title: def.label,
            icon: def.icon,
            shortcutKeys: def.keyBinding.map { ShortcutKey.from(keyBinding: $0) },
            group: groupName,
            groupPriority: groupPriority,
            keywords: commandKeywords(for: def),
            action: .dispatch(def.command),
            command: def.command
        )
    }

    /// Whether a command should show as a drill-in item with target selection.
    private static func isTargetableCommand(_ command: AppCommand) -> Bool {
        switch command {
        case .closeTab, .closePane, .extractPaneToTab, .focusPaneLeft, .focusPaneRight,
             .focusPaneUp, .focusPaneDown, .focusNextPane, .focusPrevPane,
             .switchArrangement, .deleteArrangement, .renameArrangement,
             .navigateDrawerPane:
            return true
        default:
            return false
        }
    }

    /// Build a CommandBarLevel listing available targets for a command.
    private static func buildTargetLevel(
        for def: CommandDefinition,
        store: WorkspaceStore
    ) -> CommandBarLevel {
        // Arrangement commands show arrangement targets, not generic tab/pane targets
        if def.command == .switchArrangement || def.command == .deleteArrangement || def.command == .renameArrangement {
            return buildArrangementTargetLevel(for: def, store: store)
        }

        // Drawer pane navigation shows drawer pane targets
        if def.command == .navigateDrawerPane {
            return buildDrawerPaneTargetLevel(for: def, store: store)
        }

        var items: [CommandBarItem] = []

        let appliesToTab = def.appliesTo.contains(.tab)
        let appliesToPane = def.appliesTo.contains(.pane) || def.appliesTo.contains(.floatingTerminal)

        if appliesToTab {
            items.append(contentsOf: store.tabs.enumerated().map { index, tab in
                let paneTitles = tab.paneIds.compactMap { store.pane($0)?.title }
                let title = paneTitles.count > 1
                    ? paneTitles.joined(separator: " | ")
                    : paneTitles.first ?? "Terminal"
                return CommandBarItem(
                    id: "target-tab-\(tab.id.uuidString)",
                    title: title,
                    subtitle: "Tab \(index + 1)",
                    icon: "rectangle.stack",
                    group: "Tabs",
                    groupPriority: 0,
                    action: .dispatchTargeted(def.command, target: tab.id, targetType: .tab)
                )
            })
        }

        if appliesToPane {
            for (tabIndex, tab) in store.tabs.enumerated() {
                for paneId in tab.paneIds {
                    guard let pane = store.pane(paneId) else { continue }
                    let targetType: SearchItemType
                    switch pane.source {
                    case .floating: targetType = .floatingTerminal
                    case .worktree: targetType = .pane
                    }
                    items.append(CommandBarItem(
                        id: "target-pane-\(pane.id.uuidString)",
                        title: pane.title,
                        subtitle: "Tab \(tabIndex + 1)",
                        icon: iconForPane(pane),
                        iconColor: pane.agent?.color,
                        group: "Panes",
                        groupPriority: 1,
                        action: .dispatchTargeted(def.command, target: pane.id, targetType: targetType)
                    ))
                }
            }
        }

        return CommandBarLevel(
            id: "level-\(def.command.rawValue)",
            title: def.label,
            parentLabel: "Commands",
            items: items
        )
    }

    /// Build a target level listing arrangements in the active tab for arrangement commands.
    private static func buildArrangementTargetLevel(
        for def: CommandDefinition,
        store: WorkspaceStore
    ) -> CommandBarLevel {
        var items: [CommandBarItem] = []

        if let activeTabId = store.activeTabId, let tab = store.tab(activeTabId) {
            items = tab.arrangements.compactMap { arrangement in
                // Don't show default arrangement for delete/rename
                guard !arrangement.isDefault || def.command == .switchArrangement else { return nil }
                return CommandBarItem(
                    id: "target-arrangement-\(arrangement.id.uuidString)",
                    title: arrangement.name,
                    subtitle: arrangement.isDefault ? "Default" : "\(arrangement.visiblePaneIds.count) panes",
                    icon: arrangement.isDefault ? "rectangle.3.group" : "rectangle.3.group.fill",
                    group: "Arrangements",
                    groupPriority: 0,
                    action: .dispatchTargeted(def.command, target: arrangement.id, targetType: .tab)
                )
            }
        }

        return CommandBarLevel(
            id: "level-\(def.command.rawValue)",
            title: def.label,
            parentLabel: "Commands",
            items: items
        )
    }

    /// Build a target level listing drawer panes for the active pane.
    private static func buildDrawerPaneTargetLevel(
        for def: CommandDefinition,
        store: WorkspaceStore
    ) -> CommandBarLevel {
        var items: [CommandBarItem] = []

        if let activeTabId = store.activeTabId,
           let tab = store.tab(activeTabId),
           let activePaneId = tab.activePaneId,
           let pane = store.pane(activePaneId),
           let drawer = pane.drawer {
            items = drawer.paneIds.enumerated().compactMap { index, drawerPaneId in
                guard let drawerPane = store.pane(drawerPaneId) else { return nil }
                let isActive = drawer.activePaneId == drawerPaneId
                return CommandBarItem(
                    id: "target-drawer-\(drawerPaneId.uuidString)",
                    title: drawerPane.metadata.title,
                    subtitle: isActive ? "Active" : "Drawer \(index + 1)",
                    icon: "terminal",
                    group: "Drawer Panes",
                    groupPriority: 0,
                    action: .dispatchTargeted(def.command, target: drawerPaneId, targetType: .pane)
                )
            }
        }

        return CommandBarLevel(
            id: "level-\(def.command.rawValue)",
            title: def.label,
            parentLabel: "Commands",
            items: items
        )
    }

    // MARK: - Worktree Items

    private static func worktreeItems(store: WorkspaceStore) -> [CommandBarItem] {
        store.repos.flatMap { repo in
            repo.worktrees.map { worktree in
                let worktreeId = worktree.id
                return CommandBarItem(
                    id: "wt-\(worktree.id.uuidString)",
                    title: worktree.name,
                    subtitle: "\(repo.name) · \(worktree.branch)",
                    icon: "arrow.triangle.branch",
                    iconColor: worktree.agent?.color,
                    group: Group.worktrees,
                    groupPriority: Priority.worktrees,
                    keywords: ["worktree", "branch", worktree.branch, repo.name],
                    action: .custom {
                        NotificationCenter.default.post(
                            name: .openWorktreeRequested,
                            object: nil,
                            userInfo: ["worktreeId": worktreeId]
                        )
                    }
                )
            }
        }
    }

    // MARK: - Helpers

    private static func iconForPane(_ pane: Pane) -> String {
        switch pane.content {
        case .webview: return "globe"
        case .codeViewer: return "doc.text"
        default:
            switch pane.source {
            case .floating: return "terminal.fill"
            case .worktree: return "terminal"
            }
        }
    }

    private static func keywordsForPane(_ pane: Pane, store: WorkspaceStore) -> [String] {
        var keywords = ["pane", pane.title]
        if case .webview = pane.content {
            keywords.append(contentsOf: ["web", "browser", "url"])
        } else {
            keywords.append("terminal")
        }
        if let worktreeId = pane.worktreeId, let wt = store.worktree(worktreeId) {
            keywords.append(contentsOf: [wt.name, wt.branch])
        }
        if let agent = pane.agent {
            keywords.append(agent.displayName)
        }
        return keywords
    }

    private static func isHiddenCommand(_ command: AppCommand) -> Bool {
        switch command {
        case .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
             .selectTab6, .selectTab7, .selectTab8, .selectTab9,
             .quickFind, .commandBar,
             // OAuth sign-in commands hidden until real client IDs are configured.
             // These will use ASWebAuthenticationSession to authenticate in Safari
             // (where 1Password works), then inject session cookies into WKWebView.
             .signInGitHub, .signInGoogle:
            return true
        default:
            return false
        }
    }

    private static func commandGroup(for command: AppCommand) -> (name: String, priority: Int) {
        switch command {
        case .closePane, .extractPaneToTab, .splitRight, .splitBelow, .splitLeft, .splitAbove,
             .equalizePanes, .toggleSplitZoom,
             .addDrawerPane, .toggleDrawer, .navigateDrawerPane, .closeDrawerPane:
            return (Group.paneCommands, 0)
        case .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown,
             .focusNextPane, .focusPrevPane:
            return (Group.focusCommands, 1)
        case .closeTab, .breakUpTab, .newTerminalInTab, .nextTab, .prevTab, .openNewTerminalInTab,
             .switchArrangement, .saveArrangement, .deleteArrangement, .renameArrangement:
            return (Group.tabCommands, 2)
        case .addRepo, .removeRepo, .refreshWorktrees:
            return (Group.repoCommands, 3)
        case .toggleSidebar, .newFloatingTerminal, .filterSidebar:
            return (Group.windowCommands, 4)
        case .openWebview:
            return (Group.webviewCommands, 5)
        case .signInGitHub, .signInGoogle:
            return (Group.authCommands, 6)
        default:
            return (Group.commands, 7)
        }
    }

    private static func commandKeywords(for def: CommandDefinition) -> [String] {
        var keywords: [String] = []
        // Split label into words for broader matching
        keywords.append(contentsOf: def.label.split(separator: " ").map(String.init))
        keywords.append(def.command.rawValue)
        return keywords
    }
}
