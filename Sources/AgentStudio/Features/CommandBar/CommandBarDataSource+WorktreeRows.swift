import Foundation

@MainActor
extension CommandBarDataSource {
    static func repoScopeItems(store: WorkspaceStore) -> [CommandBarItem] {
        var items: [CommandBarItem] = []
        let singleWorktreeRepos = store.repos
            .filter { $0.worktrees.count <= 1 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let multiWorktreeRepos = store.repos
            .filter { $0.worktrees.count > 1 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        for repo in singleWorktreeRepos {
            for worktree in repo.worktrees {
                let presence = buildWorktreePresence(worktree: worktree, repo: repo, store: store)
                items.append(
                    unifiedWorktreeItem(
                        worktree: worktree,
                        repo: repo,
                        presence: presence,
                        group: "Repos",
                        groupPriority: 0
                    ))
            }
        }

        for (repoIndex, repo) in multiWorktreeRepos.enumerated() {
            let groupName = "\(repo.name) (worktrees)"
            for worktree in repo.worktrees {
                let presence = buildWorktreePresence(worktree: worktree, repo: repo, store: store)
                items.append(
                    unifiedWorktreeItem(
                        worktree: worktree,
                        repo: repo,
                        presence: presence,
                        group: groupName,
                        groupPriority: repoIndex + 1
                    ))
            }
        }

        return items
    }

    static func everythingWorktreeItems(store: WorkspaceStore) -> [CommandBarItem] {
        store.repos.flatMap { repo in
            repo.worktrees.map { worktree in
                let presence = buildWorktreePresence(worktree: worktree, repo: repo, store: store)
                return unifiedWorktreeItem(
                    worktree: worktree,
                    repo: repo,
                    presence: presence,
                    group: Group.worktrees,
                    groupPriority: Priority.worktrees
                )
            }
        }
    }

    static func unifiedWorktreeItem(
        worktree: Worktree,
        repo: Repo,
        presence: WorktreePresence,
        group: String,
        groupPriority: Int
    ) -> CommandBarItem {
        CommandBarItem(
            id: "repo-wt-\(worktree.id.uuidString)",
            title: worktree.name,
            subtitle: worktreePresenceSubtitle(presence: presence, worktree: worktree),
            icon: worktree.isMainWorktree ? "star.fill" : "arrow.triangle.branch",
            group: group,
            groupPriority: groupPriority,
            keywords: ["repo", "worktree", "terminal", repo.name, worktree.name],
            hasChildren: true,
            action: .worktreeAction(presence: presence),
            command: .openWorktree
        )
    }

    static func buildWorktreePresence(
        worktree: Worktree,
        repo: Repo,
        store: WorkspaceStore
    ) -> WorktreePresence {
        let openPanes: [WorktreePaneLocation] = store.panes(for: worktree.id).compactMap { pane in
            guard let tab = store.tabContaining(paneId: pane.id),
                let tabIndex = store.tabs.firstIndex(where: { $0.id == tab.id })
            else {
                return nil
            }

            return WorktreePaneLocation(
                paneId: pane.id,
                tabId: tab.id,
                tabIndex: tabIndex,
                isActiveInTab: tab.activePaneId == pane.id
            )
        }
        .sorted { lhs, rhs in
            if lhs.tabIndex != rhs.tabIndex {
                return lhs.tabIndex < rhs.tabIndex
            }
            return lhs.paneId.uuidString < rhs.paneId.uuidString
        }

        return WorktreePresence(
            worktreeId: worktree.id,
            repoId: repo.id,
            worktreeName: worktree.name,
            repoName: repo.name,
            isMainWorktree: worktree.isMainWorktree,
            openPanes: openPanes
        )
    }

    static func buildWorktreePaneDrillInLevel(
        presence: WorktreePresence
    ) -> CommandBarLevel {
        var items = presence.openPanes.map { location in
            CommandBarItem(
                id: "wt-pane-\(location.paneId.uuidString)",
                title: "Terminal — \(presence.worktreeName)",
                subtitle: locationSubtitle(for: location),
                icon: "terminal",
                group: "Navigate to",
                groupPriority: 0,
                action: .dispatchTargeted(.focusPane, target: location.paneId, targetType: .pane),
                command: .focusPane
            )
        }

        let worktreeId = presence.worktreeId
        items.append(
            CommandBarItem(
                id: "wt-new-tab-\(worktreeId.uuidString)",
                title: "New pane in new tab",
                icon: "plus.rectangle",
                shortcutKeys: [ShortcutKey(symbol: "⌘"), ShortcutKey(symbol: "↵")],
                group: "Open new",
                groupPriority: 1,
                action: .dispatchTargeted(.openNewTerminalInTab, target: worktreeId, targetType: .worktree),
                command: .openNewTerminalInTab
            ))
        items.append(
            CommandBarItem(
                id: "wt-add-pane-\(worktreeId.uuidString)",
                title: "New pane in current tab",
                icon: "rectangle.split.2x1",
                shortcutKeys: [ShortcutKey(symbol: "⌥"), ShortcutKey(symbol: "↵")],
                group: "Open new",
                groupPriority: 1,
                action: .dispatchTargeted(.openWorktreeInPane, target: worktreeId, targetType: .worktree),
                command: .openWorktreeInPane
            ))

        return CommandBarLevel(
            id: "level-wt-\(worktreeId.uuidString)",
            title: presence.worktreeName,
            parentLabel: presence.repoName,
            scopeLabel: "Worktrees · Actions",
            items: items
        )
    }

    static func buildWorktreeOpenChoiceLevel(
        presence: WorktreePresence,
        hasTabsOpen: Bool
    ) -> CommandBarLevel {
        let worktreeId = presence.worktreeId
        var items = [
            CommandBarItem(
                id: "wt-choice-new-tab-\(worktreeId.uuidString)",
                title: "New pane in new tab",
                icon: "plus.rectangle",
                shortcutKeys: [ShortcutKey(symbol: "⌘"), ShortcutKey(symbol: "↵")],
                group: "Open",
                groupPriority: 0,
                action: .dispatchTargeted(.openNewTerminalInTab, target: worktreeId, targetType: .worktree),
                command: .openNewTerminalInTab
            )
        ]

        if hasTabsOpen {
            items.append(
                CommandBarItem(
                    id: "wt-choice-add-pane-\(worktreeId.uuidString)",
                    title: "New pane in current tab",
                    icon: "rectangle.split.2x1",
                    shortcutKeys: [ShortcutKey(symbol: "⌥"), ShortcutKey(symbol: "↵")],
                    group: "Open",
                    groupPriority: 0,
                    action: .dispatchTargeted(.openWorktreeInPane, target: worktreeId, targetType: .worktree),
                    command: .openWorktreeInPane
                ))
        }

        return CommandBarLevel(
            id: "level-wt-choice-\(worktreeId.uuidString)",
            title: presence.worktreeName,
            parentLabel: presence.repoName,
            scopeLabel: "Worktrees · Open",
            items: items
        )
    }

    static func worktreePresenceSubtitle(
        presence: WorktreePresence,
        worktree: Worktree
    ) -> String? {
        switch presence.openState {
        case .notOpen:
            return worktree.isMainWorktree ? "main worktree" : nil
        case .singlePane:
            guard let location = presence.openPanes.first else { return nil }
            return "● Tab \(location.tabIndex + 1) · 1 pane"
        case .multiplePanes:
            let paneCount = presence.openPanes.count
            let tabCount = presence.distinctTabCount
            if tabCount == 1, let location = presence.openPanes.first {
                return "● \(paneCount) panes · Tab \(location.tabIndex + 1)"
            }
            return "● \(paneCount) panes · \(tabCount) tabs"
        }
    }

    private static func locationSubtitle(for location: WorktreePaneLocation) -> String {
        location.isActiveInTab ? "Tab \(location.tabIndex + 1) · Active" : "Tab \(location.tabIndex + 1)"
    }
}
