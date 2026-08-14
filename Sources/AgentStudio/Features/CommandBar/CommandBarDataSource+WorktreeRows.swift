import AgentStudioCore
import AgentStudioInfrastructure
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
    static func repoScopeItems(
        store: WorkspaceStore,
        dispatcher: any AppCommandDispatching,
        itemCache: CommandBarRepoScopeItemCache? = nil
    ) -> [CommandBarItem] {
        if let itemCache {
            return itemCache.items(
                store: store,
                group: Group.repositories,
                groupPriority: Priority.repositories,
                dispatcher: dispatcher
            )
        }
        return allRepoItems(
            store: store,
            group: Group.repositories,
            groupPriority: Priority.repositories,
            dispatcher: dispatcher
        )
    }

    static func allRepoItems(
        store: WorkspaceStore,
        group: String,
        groupPriority: Int,
        dispatcher _: any AppCommandDispatching
    ) -> [CommandBarItem] {
        let presenceByWorktreeId = buildWorktreePresenceByWorktreeId(store: store)
        return store.repositoryTopologyAtom.repos
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { repo in
                repoRootItem(
                    repo: repo,
                    presenceByWorktreeId: presenceByWorktreeId,
                    group: group,
                    groupPriority: groupPriority
                )
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
                    groupPriority: Priority.repositories
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

    static func repoRootItem(
        repo: Repo,
        store: WorkspaceStore,
        dispatcher _: any AppCommandDispatching
    ) -> CommandBarItem {
        let presenceByWorktreeId = buildWorktreePresenceByWorktreeId(store: store)
        return repoRootItem(
            repo: repo,
            presenceByWorktreeId: presenceByWorktreeId,
            group: Group.repos,
            groupPriority: Priority.repos
        )
    }

    static func repoRootItem(
        repo: Repo,
        presenceByWorktreeId: [UUID: WorktreePresence],
        group: String,
        groupPriority: Int
    ) -> CommandBarItem {
        CommandBarItem(
            id: "repo-\(repo.id.uuidString)",
            title: repo.name,
            subtitle: repoRootSubtitle(repo: repo, presenceByWorktreeId: presenceByWorktreeId),
            icon: .system(.folder),
            group: group,
            groupPriority: groupPriority,
            keywords: repoRootKeywords(repo: repo),
            hasChildren: true,
            action: .navigateRepo(repositoryID: repo.id)
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
        buildWorktreePresenceByWorktreeId(
            repos: store.repositoryTopologyAtom.repos,
            locationsByWorktreeId: worktreeLocationsByWorktreeId(store: store)
        )
    }

    static func worktreeLocationsByWorktreeId(
        store: WorkspaceStore
    ) -> [UUID: [WorkspacePaneLocation]] {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        let locationsByWorktreeId = atom(\.workspaceLookup).paneLocationsByWorktreeId(
            repositoryTopology: store.repositoryTopologyAtom,
            workspacePane: store.paneAtom,
            workspaceTab: workspaceTab
        )

        return locationsByWorktreeId
    }

    static func buildWorktreePresenceByWorktreeId(
        repos: [Repo],
        locationsByWorktreeId: [UUID: [WorkspacePaneLocation]]
    ) -> [UUID: WorktreePresence] {
        var presenceByWorktreeId: [UUID: WorktreePresence] = [:]
        for repo in repos {
            for worktree in repo.worktrees where presenceByWorktreeId[worktree.id] == nil {
                presenceByWorktreeId[worktree.id] = WorktreePresence(
                    worktreeId: worktree.id,
                    repoId: repo.id,
                    worktreeName: worktree.name,
                    repoName: repo.name,
                    isMainWorktree: worktree.isMainWorktree,
                    openPanes: locationsByWorktreeId[worktree.id] ?? []
                )
            }
        }
        return presenceByWorktreeId
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
            repositoryTopology: store.repositoryTopologyAtom,
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

    static func buildRepoLevel(
        repo: Repo,
        store: WorkspaceStore,
        dispatcher: any AppCommandDispatching
    ) -> CommandBarLevel {
        buildRepoLevel(
            repo: repo,
            store: store,
            presenceByWorktreeId: buildWorktreePresenceByWorktreeId(store: store),
            dispatcher: dispatcher
        )
    }

    static func buildRepoLevel(
        repo: Repo,
        store: WorkspaceStore,
        presenceByWorktreeId: [UUID: WorktreePresence],
        dispatcher: any AppCommandDispatching
    ) -> CommandBarLevel {
        let defaultWorktree = repo.worktrees.first(where: \.isMainWorktree) ?? repo.worktrees.first
        var items: [CommandBarItem] = []
        let canOpenInCurrentTab = store.tabLayoutAtom.activeTabId != nil

        if let defaultWorktree {
            items.append(
                contentsOf: terminalWorktreeActionItems(
                    worktreeId: defaultWorktree.id,
                    canOpenInCurrentTab: canOpenInCurrentTab
                )
            )
            items.append(
                copyPathItem(
                    id: "repo-\(repo.id.uuidString)", path: defaultWorktree.path, group: "Path", groupPriority: 1)
            )
            items.append(
                revealInFinderItem(
                    id: "repo-\(repo.id.uuidString)",
                    path: defaultWorktree.path,
                    group: "Path",
                    groupPriority: 1
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
                        canOpenInCurrentTab: store.tabLayoutAtom.activeTabId != nil,
                        dispatcher: dispatcher
                    )
                    return CommandBarItem(
                        id: "repo-wt-\(worktree.id.uuidString)",
                        title: worktree.name,
                        subtitle: worktreePresenceSubtitle(presence: presence, worktree: worktree),
                        icon: worktree.isMainWorktree ? .system(.starFill) : .system(.arrowTriangleBranch),
                        group: "Worktrees",
                        groupPriority: 2,
                        keywords: worktreeKeywords(worktree: worktree, repo: repo, includeFullPath: true),
                        hasChildren: true,
                        action: .navigate(level),
                        command: .openWorktree
                    )
                }
        )

        if let defaultWorktree {
            let bridgeResolution =
                dispatcher
                .bridgePaneCommandTarget(worktreeId: defaultWorktree.id)?
                .resolution ?? .create
            items.append(
                contentsOf: bridgeWorktreeActionItems(
                    worktreeId: defaultWorktree.id,
                    resolution: bridgeResolution,
                    groupPriority: 3
                )
            )
        }

        return CommandBarLevel(
            id: "level-repo-\(repo.id.uuidString)",
            title: repo.name,
            parentLabel: "Repos",
            scopeLabel: "Repository",
            breadcrumbIcon: .coloredRepo(
                colorHex: AppStyles.Shell.Sidebar.accentPaletteHexes[0]
            ),
            items: items
        )
    }

    static func emptyWorktreePresence(worktree: Worktree, repo: Repo) -> WorktreePresence {
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
        canOpenInCurrentTab: Bool,
        dispatcher: any AppCommandDispatching
    ) -> CommandBarLevel {
        let worktreeId = presence.worktreeId
        let bridgeResolution =
            dispatcher.bridgePaneCommandTarget(worktreeId: worktreeId)?
            .resolution ?? .create
        var items = terminalWorktreeActionItems(
            worktreeId: worktreeId,
            canOpenInCurrentTab: canOpenInCurrentTab
        )
        items.append(
            copyPathItem(id: "wt-\(worktreeId.uuidString)", path: worktree.path, group: "Path", groupPriority: 1)
        )
        items.append(
            revealInFinderItem(
                id: "wt-\(worktreeId.uuidString)",
                path: worktree.path,
                group: "Path",
                groupPriority: 1
            )
        )
        items.append(
            contentsOf: bridgeWorktreeActionItems(
                worktreeId: worktreeId,
                resolution: bridgeResolution,
                groupPriority: 2
            )
        )

        items.append(
            contentsOf: presence.openPanes.compactMap { location in
                guard
                    let focusPaneSpec = CommandBarCommandPresentation.targetedSpec(
                        for: .focusPane,
                        targetType: .pane
                    )
                else {
                    return nil
                }
                return CommandBarItem(
                    id: "wt-pane-\(location.paneId.uuidString)",
                    title: "Terminal — \(presence.worktreeName)",
                    subtitle: locationSubtitle(for: location),
                    icon: .system(.terminal),
                    group: "Navigate to",
                    groupPriority: 3,
                    action: .dispatchTargeted(
                        focusPaneSpec.command,
                        target: location.paneId,
                        targetType: .pane
                    ),
                    command: focusPaneSpec.command
                )
            }
        )

        return CommandBarLevel(
            id: "level-wt-\(worktreeId.uuidString)",
            title: presence.worktreeName,
            parentLabel: presence.repoName,
            scopeLabel: "Worktree",
            breadcrumbIcon: .checkout(
                colorHex: AppStyles.Shell.Sidebar.accentPaletteHexes[0],
                isMain: worktree.isMainWorktree
            ),
            items: items
        )
    }

    private static func terminalWorktreeActionItems(
        worktreeId: UUID,
        canOpenInCurrentTab: Bool
    ) -> [CommandBarItem] {
        var items: [CommandBarItem] = []
        if canOpenInCurrentTab,
            let openInPaneSpec = CommandBarCommandPresentation.commandBarTargetedSpec(
                for: .openWorktreeInPane,
                targetType: .worktree
            )
        {
            let currentTabShortcut = ShortcutTrigger(key: .enter, modifiers: [.option])
            items.append(
                CommandBarItem(
                    id: "wt-add-pane-\(worktreeId.uuidString)",
                    title: "New pane in current tab",
                    icon: .system(.rectangleSplit2x1),
                    shortcutTrigger: currentTabShortcut,
                    group: "Terminal",
                    groupPriority: 0,
                    action: .dispatchTargeted(
                        openInPaneSpec.command,
                        target: worktreeId,
                        targetType: .worktree
                    ),
                    command: openInPaneSpec.command
                )
            )
        }

        let newTabShortcut = ShortcutTrigger(key: .enter, modifiers: [.command])
        if let openInNewTabSpec = CommandBarCommandPresentation.commandBarTargetedSpec(
            for: .openNewTerminalInTab,
            targetType: .worktree
        ) {
            items.append(
                CommandBarItem(
                    id: "wt-new-tab-\(worktreeId.uuidString)",
                    title: openInNewTabSpec.label,
                    icon: .system(.plusRectangle),
                    shortcutTrigger: newTabShortcut,
                    group: "Terminal",
                    groupPriority: 0,
                    action: .dispatchTargeted(
                        openInNewTabSpec.command,
                        target: worktreeId,
                        targetType: .worktree
                    ),
                    command: openInNewTabSpec.command
                ))
        }
        return items
    }

    static func buildWorktreeActionsLevel(
        presence: WorktreePresence,
        canOpenInCurrentTab: Bool,
        dispatcher: any AppCommandDispatching
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
            canOpenInCurrentTab: canOpenInCurrentTab,
            dispatcher: dispatcher
        )
    }

    private static func bridgeWorktreeActionItems(
        worktreeId: UUID,
        resolution: BridgePaneCommandResolution,
        groupPriority: Int
    ) -> [CommandBarItem] {
        let candidates: [(command: AppCommand, id: String, keywords: [String])] = [
            (.showBridgeReview, "wt-review-\(worktreeId.uuidString)", ["review", "bridge", "diff"]),
            (.showBridgeFiles, "wt-files-\(worktreeId.uuidString)", ["files", "bridge", "worktree"]),
            (
                .openBridgeReviewInNewTab,
                "wt-review-new-tab-\(worktreeId.uuidString)",
                ["review", "bridge", "diff", "new", "tab"]
            ),
            (
                .openBridgeFilesInNewTab,
                "wt-files-new-tab-\(worktreeId.uuidString)",
                ["files", "bridge", "worktree", "new", "tab"]
            ),
        ]
        return candidates.compactMap { candidate in
            guard
                let commandSpec = CommandBarCommandPresentation.commandBarTargetedSpec(
                    for: candidate.command,
                    targetType: .worktree
                )
            else {
                return nil
            }
            let title: String
            switch candidate.command {
            case .showBridgeReview, .showBridgeFiles:
                title = resolution.contextualLabel(for: candidate.command)
            default:
                title = commandSpec.label
            }
            return CommandBarItem(
                id: candidate.id,
                title: title,
                icon: commandSpec.icon,
                group: "Panes",
                groupPriority: groupPriority,
                keywords: candidate.keywords,
                action: .dispatchTargeted(
                    commandSpec.command,
                    target: worktreeId,
                    targetType: .worktree
                ),
                command: commandSpec.command
            )
        }
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
