import AppKit
import Foundation
import os.log

private let commandBarWorktreeLogger = Logger(subsystem: "com.agentstudio", category: "CommandBarWorktreePresence")

struct CommandBarPathActionFailure: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case copyPath
        case revealInFinder
    }

    let action: Action
    let path: URL
}

typealias CommandBarPathActionFailureHandler = @MainActor @Sendable (CommandBarPathActionFailure) -> Void

@MainActor
extension CommandBarDataSource {
    static func repoScopeItems(store: WorkspaceStore) -> [CommandBarItem] {
        let presenceByWorktreeId = buildWorktreePresenceByWorktreeId(store: store)
        return store.repositoryTopologyAtom.repos
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { repo in
                repoRootItem(repo: repo, store: store, presenceByWorktreeId: presenceByWorktreeId)
            }
    }

    static func everythingWorktreeItems(store: WorkspaceStore) -> [CommandBarItem] {
        let presenceByWorktreeId = buildWorktreePresenceByWorktreeId(store: store)
        return store.repositoryTopologyAtom.repos.flatMap { repo in
            repo.worktrees.map { worktree in
                let presence =
                    presenceByWorktreeId[worktree.id]
                    ?? emptyWorktreePresence(worktree: worktree, repo: repo)
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
            icon: worktree.isMainWorktree ? .system(.starFill) : .system(.arrowTriangleBranch),
            group: group,
            groupPriority: groupPriority,
            keywords: worktreeKeywords(worktree: worktree, repo: repo),
            hasChildren: true,
            action: .worktreeAction(presence: presence),
            command: .openWorktree
        )
    }

    static func repoRootItem(repo: Repo, store: WorkspaceStore) -> CommandBarItem {
        let presenceByWorktreeId = buildWorktreePresenceByWorktreeId(store: store)
        return repoRootItem(repo: repo, store: store, presenceByWorktreeId: presenceByWorktreeId)
    }

    static func repoRootItem(
        repo: Repo,
        store: WorkspaceStore,
        presenceByWorktreeId: [UUID: WorktreePresence]
    ) -> CommandBarItem {
        let level = buildRepoLevel(repo: repo, store: store, presenceByWorktreeId: presenceByWorktreeId)
        return CommandBarItem(
            id: "repo-\(repo.id.uuidString)",
            title: repo.name,
            subtitle: repoRootSubtitle(repo: repo, presenceByWorktreeId: presenceByWorktreeId),
            icon: .system(.folder),
            group: "Repos",
            groupPriority: 0,
            keywords: repoRootKeywords(repo: repo),
            hasChildren: true,
            action: .navigateRepo(level)
        )
    }

    static func repoRootKeywords(repo: Repo) -> [String] {
        var keywords = ["repo", repo.name, repo.repoPath.lastPathComponent]
        keywords.append(contentsOf: repo.tags)
        keywords.append(contentsOf: repo.worktrees.map(\.name))
        keywords.append(contentsOf: repo.worktrees.map { $0.path.lastPathComponent })
        return keywords
    }

    static func repoRootSubtitle(repo: Repo, store: WorkspaceStore) -> String? {
        repoRootSubtitle(repo: repo, presenceByWorktreeId: buildWorktreePresenceByWorktreeId(store: store))
    }

    static func repoRootSubtitle(repo: Repo, presenceByWorktreeId: [UUID: WorktreePresence]) -> String? {
        let openPanes = repo.worktrees.flatMap { presenceByWorktreeId[$0.id]?.openPanes ?? [] }
        let openPaneCount = openPanes.count
        let worktreeCount = repo.worktrees.count

        var parts: [String] = []
        if worktreeCount == 1 {
            if let first = openPanes.first, openPaneCount == 1 {
                parts.append("● Tab \(first.tabIndex + 1) · 1 pane")
            } else if openPaneCount > 1 {
                parts.append("● \(openPaneCount) panes")
            }
        } else {
            parts.append("\(worktreeCount) worktrees")
            if openPaneCount > 0 {
                parts.append("● \(openPaneCount) open")
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func buildWorktreePresenceByWorktreeId(store: WorkspaceStore) -> [UUID: WorktreePresence] {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        let locationsByWorktreeId = atom(\.workspaceLookup).paneLocationsByWorktreeId(
            workspacePane: store.paneAtom,
            workspaceTab: workspaceTab
        )

        return Dictionary(
            uniqueKeysWithValues: store.repositoryTopologyAtom.repos.flatMap { repo in
                repo.worktrees.map { worktree in
                    (
                        worktree.id,
                        WorktreePresence(
                            worktreeId: worktree.id,
                            repoId: repo.id,
                            worktreeName: worktree.name,
                            repoName: repo.name,
                            isMainWorktree: worktree.isMainWorktree,
                            openPanes: locationsByWorktreeId[worktree.id] ?? []
                        )
                    )
                }
            }
        )
    }

    static func buildWorktreePresence(
        worktree: Worktree,
        repo: Repo,
        store: WorkspaceStore
    ) -> WorktreePresence {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        let openPanes = atom(\.workspaceLookup).paneLocations(
            for: worktree.id,
            workspacePane: store.paneAtom,
            workspaceTab: workspaceTab
        )

        return WorktreePresence(
            worktreeId: worktree.id,
            repoId: repo.id,
            worktreeName: worktree.name,
            repoName: repo.name,
            isMainWorktree: worktree.isMainWorktree,
            openPanes: openPanes
        )
    }

    static func buildRepoLevel(repo: Repo, store: WorkspaceStore) -> CommandBarLevel {
        buildRepoLevel(
            repo: repo,
            store: store,
            presenceByWorktreeId: buildWorktreePresenceByWorktreeId(store: store)
        )
    }

    static func buildRepoLevel(
        repo: Repo,
        store: WorkspaceStore,
        presenceByWorktreeId: [UUID: WorktreePresence]
    ) -> CommandBarLevel {
        let defaultWorktree = repo.worktrees.first(where: \.isMainWorktree) ?? repo.worktrees.first
        var items: [CommandBarItem] = []

        if let defaultWorktree {
            items.append(
                copyPathItem(
                    id: "repo-\(repo.id.uuidString)", path: defaultWorktree.path, group: "Open", groupPriority: 0)
            )
            items.append(
                revealInFinderItem(
                    id: "repo-\(repo.id.uuidString)",
                    path: defaultWorktree.path,
                    group: "Open",
                    groupPriority: 0
                )
            )
        }

        items.append(
            contentsOf: repo.worktrees
                .sorted { lhs, rhs in
                    if lhs.isMainWorktree != rhs.isMainWorktree {
                        return lhs.isMainWorktree
                    }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                .map { worktree in
                    let presence =
                        presenceByWorktreeId[worktree.id]
                        ?? emptyWorktreePresence(worktree: worktree, repo: repo)
                    let level = buildWorktreeActionsLevel(
                        worktree: worktree,
                        presence: presence,
                        canOpenInCurrentTab: store.tabLayoutAtom.activeTabId != nil
                    )
                    return CommandBarItem(
                        id: "repo-wt-\(worktree.id.uuidString)",
                        title: worktree.name,
                        subtitle: worktreePresenceSubtitle(presence: presence, worktree: worktree),
                        icon: worktree.isMainWorktree ? .system(.starFill) : .system(.arrowTriangleBranch),
                        group: "Worktrees",
                        groupPriority: 1,
                        keywords: worktreeKeywords(worktree: worktree, repo: repo, includeFullPath: true),
                        hasChildren: true,
                        action: .navigate(level),
                        command: .openWorktree
                    )
                }
        )

        return CommandBarLevel(
            id: "level-repo-\(repo.id.uuidString)",
            title: repo.name,
            parentLabel: "Repos",
            scopeLabel: "Repo",
            items: items
        )
    }

    private static func emptyWorktreePresence(worktree: Worktree, repo: Repo) -> WorktreePresence {
        WorktreePresence(
            worktreeId: worktree.id,
            repoId: repo.id,
            worktreeName: worktree.name,
            repoName: repo.name,
            isMainWorktree: worktree.isMainWorktree,
            openPanes: []
        )
    }

    private static func worktreeKeywords(worktree: Worktree, repo: Repo, includeFullPath: Bool = false) -> [String] {
        var keywords = ["repo", "worktree", "terminal", repo.name, worktree.name, worktree.path.lastPathComponent]
        if includeFullPath {
            keywords.append(worktree.path.path)
        }
        keywords.append(contentsOf: repo.tags)
        return keywords
    }

    static func buildWorktreeActionsLevel(
        worktree: Worktree,
        presence: WorktreePresence,
        canOpenInCurrentTab: Bool
    ) -> CommandBarLevel {
        let worktreeId = presence.worktreeId
        let newTabShortcut = ShortcutTrigger(key: .enter, modifiers: [.command])
        var items = [
            copyPathItem(id: "wt-\(worktreeId.uuidString)", path: worktree.path, group: "Open", groupPriority: 0),
            revealInFinderItem(id: "wt-\(worktreeId.uuidString)", path: worktree.path, group: "Open", groupPriority: 0),
            CommandBarItem(
                id: "wt-new-tab-\(worktreeId.uuidString)",
                title: "New pane in new tab",
                icon: .system(.plusRectangle),
                shortcutTrigger: newTabShortcut,
                group: "Open",
                groupPriority: 0,
                action: .dispatchTargeted(.openNewTerminalInTab, target: worktreeId, targetType: .worktree),
                command: .openNewTerminalInTab
            ),
        ]

        if canOpenInCurrentTab {
            let currentTabShortcut = ShortcutTrigger(key: .enter, modifiers: [.option])
            items.append(
                CommandBarItem(
                    id: "wt-add-pane-\(worktreeId.uuidString)",
                    title: "New pane in current tab",
                    icon: .system(.rectangleSplit2x1),
                    shortcutTrigger: currentTabShortcut,
                    group: "Open",
                    groupPriority: 0,
                    action: .dispatchTargeted(.openWorktreeInPane, target: worktreeId, targetType: .worktree),
                    command: .openWorktreeInPane
                ))
        }

        items.append(
            contentsOf: presence.openPanes.map { location in
                CommandBarItem(
                    id: "wt-pane-\(location.paneId.uuidString)",
                    title: "Terminal — \(presence.worktreeName)",
                    subtitle: locationSubtitle(for: location),
                    icon: .system(.terminal),
                    group: "Navigate to",
                    groupPriority: 1,
                    action: .dispatchTargeted(.focusPane, target: location.paneId, targetType: .pane),
                    command: .focusPane
                )
            }
        )

        return CommandBarLevel(
            id: "level-wt-\(worktreeId.uuidString)",
            title: presence.worktreeName,
            parentLabel: presence.repoName,
            scopeLabel: presence.repoName,
            items: items
        )
    }

    static func buildWorktreeActionsLevel(
        presence: WorktreePresence,
        canOpenInCurrentTab: Bool
    ) -> CommandBarLevel {
        let worktree = Worktree(
            id: presence.worktreeId,
            repoId: presence.repoId,
            name: presence.worktreeName,
            path: URL(filePath: "/tmp/\(presence.worktreeName)"),
            isMainWorktree: presence.isMainWorktree
        )
        return buildWorktreeActionsLevel(
            worktree: worktree,
            presence: presence,
            canOpenInCurrentTab: canOpenInCurrentTab
        )
    }

    static func copyPathItem(
        id: String,
        path: URL,
        group: String,
        groupPriority: Int,
        pathActions: any PathActionsExecuting = LivePathActionsExecutor(),
        onPathActionFailure: @escaping CommandBarPathActionFailureHandler = defaultPathActionFailureHandler
    ) -> CommandBarItem {
        let spec = LocalActionSpec.copyPath.actionSpec
        return CommandBarItem(
            id: "\(id)-copy-path",
            title: spec.label,
            icon: spec.icon,
            shortcutTrigger: AppShortcut.copyCurrentPanePath.trigger,
            group: group,
            groupPriority: groupPriority,
            keywords: ["copy", "path", path.path],
            action: .custom {
                Task { @MainActor in
                    if !pathActions.copyPath(path) {
                        onPathActionFailure(CommandBarPathActionFailure(action: .copyPath, path: path))
                    }
                }
            }
        )
    }

    static func revealInFinderItem(
        id: String,
        path: URL,
        group: String,
        groupPriority: Int,
        pathActions: any PathActionsExecuting = LivePathActionsExecutor(),
        onPathActionFailure: @escaping CommandBarPathActionFailureHandler = defaultPathActionFailureHandler
    ) -> CommandBarItem {
        let spec = LocalActionSpec.revealInFinder.actionSpec
        return CommandBarItem(
            id: "\(id)-reveal-finder",
            title: spec.label,
            icon: spec.icon,
            shortcutTrigger: AppShortcut.openPaneLocationInFinder.trigger,
            group: group,
            groupPriority: groupPriority,
            keywords: ["reveal", "finder", "open", "path", path.path],
            action: .custom {
                Task { @MainActor in
                    if !pathActions.revealInFinder(path) {
                        onPathActionFailure(CommandBarPathActionFailure(action: .revealInFinder, path: path))
                    }
                }
            }
        )
    }

    private static let defaultPathActionFailureHandler: CommandBarPathActionFailureHandler = { failure in
        NSSound.beep()
        commandBarWorktreeLogger.warning(
            "Command bar path action failed action=\(String(describing: failure.action), privacy: .public) path=\(failure.path.path, privacy: .public)"
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
                return "● Tab \(location.tabIndex + 1) · \(paneCount) panes"
            }
            return "● \(paneCount) panes · \(tabCount) tabs"
        }
    }

    private static func locationSubtitle(for location: WorkspacePaneLocation) -> String {
        let base = "Tab \(location.tabIndex + 1) · Pane \(location.paneIndexInTab + 1)"
        return location.isActiveInTab ? "\(base) · Active" : base
    }
}
