import AgentStudioCore
import Foundation

enum CommandBarRootQueryState: Equatable, Sendable {
    case empty
    case meaningful
}

@MainActor
extension CommandBarDataSource {
    static func emptyRootProjection(
        scope: CommandBarScope,
        canonicalItems: [CommandBarItem],
        recentCommands: [AppCommand],
        store: WorkspaceStore,
        focus: WorkspacePaneFocus
    ) -> [CommandBarItem] {
        switch scope {
        case .everything:
            return projectRecentRepositories(
                canonicalItems: canonicalItems,
                visibleCap: 3,
                store: store
            )
        case .quickOpen:
            return projectQuickOpenLocations(
                canonicalItems: canonicalItems,
                store: store,
                focus: focus
            )
        case .repos:
            return projectRecentRepositoryScope(
                canonicalItems: canonicalItems,
                store: store
            )
        case .panes:
            return projectRecentPanes(
                canonicalItems: canonicalItems,
                store: store,
                focusedPaneID: focus.activePaneId
            )
        case .commands:
            return projectRecentCommands(
                canonicalItems: canonicalItems,
                recentCommands: recentCommands
            )
        case .inbox:
            return canonicalItems
        }
    }

    private static func projectRecentRepositories(
        canonicalItems: [CommandBarItem],
        visibleCap: Int,
        store: WorkspaceStore
    ) -> [CommandBarItem] {
        let canonicalByID = Dictionary(uniqueKeysWithValues: canonicalItems.map { ($0.id, $0) })
        let recentRows = resolvedRecentRepositories(store: store)
            .prefix(visibleCap)
            .compactMap { stableKey, repository, defaultWorktree -> CommandBarItem? in
                guard let canonical = canonicalByID["repo-\(repository.id.uuidString)"] else {
                    return nil
                }
                return canonical.projected(
                    group: Group.recentRepositories,
                    groupPriority: Priority.recentRepositories,
                    action: .activateRecent(
                        .repository(repositoryStableKey: stableKey)
                    ),
                    hasChildren: true,
                    accessibilityLabel: [
                        repository.name,
                        defaultWorktree.name,
                        defaultWorktree.path.path,
                    ].joined(separator: ", "),
                    accessibilityHint: "Show repository actions"
                )
            }
        let promotedIDs = Set(recentRows.map(\.id))
        return recentRows + canonicalItems.filter { !promotedIDs.contains($0.id) }
    }

    private static func projectRecentRepositoryScope(
        canonicalItems: [CommandBarItem],
        store: WorkspaceStore
    ) -> [CommandBarItem] {
        let repositoryProjection = projectRecentRepositories(
            canonicalItems: canonicalItems,
            visibleCap: 5,
            store: store
        )
        let promotedRepositoryIDs = Set(
            repositoryProjection
                .filter { $0.group == Group.recentRepositories }
                .map(\.id)
        )
        let recentWorktrees = resolvedRecentWorktrees(store: store)
            .prefix(5)
            .map { stableKey, repository, worktree in
                let presence = buildWorktreePresence(
                    worktree: worktree,
                    repo: repository,
                    store: store
                )
                return CommandBarItem(
                    id: "repo-wt-\(worktree.id.uuidString)",
                    title: worktree.name,
                    subtitle: repository.name,
                    icon: worktree.isMainWorktree ? .system(.starFill) : .system(.arrowTriangleBranch),
                    group: Group.recentWorktrees,
                    groupPriority: Priority.recentWorktrees,
                    keywords: ["repo", "worktree", repository.name, worktree.name, worktree.path.lastPathComponent],
                    hasChildren: true,
                    action: .activateRecent(
                        .worktree(worktreeStableKey: stableKey)
                    ),
                    command: .openWorktree,
                    accessibilityLabel: [
                        worktree.name,
                        repository.name,
                        worktree.path.path,
                        presence.openState == .notOpen ? "Not open" : "Open",
                    ].joined(separator: ", "),
                    accessibilityHint: "Show worktree actions"
                )
            }

        let recentRepositories = repositoryProjection.filter {
            $0.group == Group.recentRepositories
        }
        let remainingRepositories = canonicalItems.filter {
            !promotedRepositoryIDs.contains($0.id)
        }
        return recentRepositories + recentWorktrees + remainingRepositories
    }

    private static func projectRecentPanes(
        canonicalItems: [CommandBarItem],
        store: WorkspaceStore,
        focusedPaneID: UUID?
    ) -> [CommandBarItem] {
        let workspaceID = store.identityAtom.workspaceId
        let recencyAtom = atom(\.workspaceEntityRecency)
        guard recencyAtom.workspaceID == workspaceID else {
            return canonicalItems
        }

        let canonicalByID = Dictionary(uniqueKeysWithValues: canonicalItems.map { ($0.id, $0) })
        let recentRows = recencyAtom.recentEntities.compactMap { recency -> CommandBarItem? in
            guard case .pane(let paneID) = recency.entity else { return nil }
            guard paneID != focusedPaneID else { return nil }
            guard
                WorkspacePaneRecencyEligibility.isEligibleForRecording(
                    pane: store.paneAtom.pane(paneID),
                    workspaceMatches: true,
                    tabs: store.tabLayoutAtom.tabs,
                    targetableTabID: store.tabLayoutAtom.tabContaining(paneId: paneID)?.id
                ),
                let canonical = canonicalByID["pane-\(paneID.uuidString)"]
            else {
                return nil
            }
            return canonical.projected(
                group: Group.recentPanes,
                groupPriority: 0,
                action: .activateRecent(.pane(paneID: paneID, workspaceID: workspaceID)),
                hasChildren: false,
                accessibilityHint: "Focus pane"
            )
        }
        .prefix(5)
        .map(\.self)

        let promotedIDs = Set(recentRows.map(\.id))
        return recentRows + canonicalItems.filter { !promotedIDs.contains($0.id) }
    }

    private static func projectRecentCommands(
        canonicalItems: [CommandBarItem],
        recentCommands: [AppCommand]
    ) -> [CommandBarItem] {
        let canonicalByCommand = Dictionary(
            uniqueKeysWithValues: canonicalItems.compactMap { item in
                item.command.map { ($0, item) }
            }
        )
        let recentRows = recentCommands.compactMap { command in
            canonicalByCommand[command]?.projected(
                group: Group.recentCommands,
                groupPriority: 0
            )
        }
        .prefix(3)
        .map(\.self)

        let promotedIDs = Set(recentRows.map(\.id))
        return recentRows + canonicalItems.filter { !promotedIDs.contains($0.id) }
    }

    private static func resolvedRecentRepositories(
        store: WorkspaceStore
    ) -> [(stableKey: String, repository: Repo, defaultWorktree: Worktree)] {
        atom(\.applicationEntityRecency).recentEntities.compactMap { recency in
            guard case .repository(let stableKey) = recency.entity else { return nil }
            guard let repository = store.repositoryTopologyAtom.repo(stableKey: stableKey) else {
                return nil
            }
            guard !store.repositoryTopologyAtom.isRepoUnavailable(repository.id) else {
                return nil
            }
            guard
                let defaultWorktree =
                    repository.worktrees.first(where: \.isMainWorktree)
                    ?? repository.worktrees.first
            else {
                return nil
            }
            return (stableKey, repository, defaultWorktree)
        }
    }

    private static func resolvedRecentWorktrees(
        store: WorkspaceStore
    ) -> [(stableKey: String, repository: Repo, worktree: Worktree)] {
        atom(\.applicationEntityRecency).recentEntities.compactMap { recency in
            guard case .worktree(let stableKey) = recency.entity else { return nil }
            guard
                let worktree = store.repositoryTopologyAtom.worktree(stableKey: stableKey),
                let repository = store.repositoryTopologyAtom.repo(containing: worktree.id),
                !store.repositoryTopologyAtom.isRepoUnavailable(repository.id)
            else {
                return nil
            }
            return (stableKey, repository, worktree)
        }
    }
}
