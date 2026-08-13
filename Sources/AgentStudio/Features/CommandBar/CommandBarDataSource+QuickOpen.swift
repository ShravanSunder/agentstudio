import AgentStudioCore
import Foundation

@MainActor
extension CommandBarDataSource {
    static func quickOpenItems(
        store: WorkspaceStore,
        dispatcher: any AppCommandDispatching
    ) -> [CommandBarItem] {
        let presenceByWorktreeID = buildWorktreePresenceByWorktreeId(store: store)
        return store.repositoryTopologyAtom.repos
            .filter { !store.repositoryTopologyAtom.isRepoUnavailable($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .flatMap { repository -> [CommandBarItem] in
                guard let defaultWorktree = quickOpenDefaultWorktree(for: repository) else {
                    return []
                }

                let repositoryItem = repoRootItem(
                    repo: repository,
                    presenceByWorktreeId: presenceByWorktreeID,
                    group: Group.repositoriesAndWorktrees,
                    groupPriority: Priority.repositoriesAndWorktrees
                )
                .projected(
                    group: Group.repositoriesAndWorktrees,
                    groupPriority: Priority.repositoriesAndWorktrees,
                    action: .quickOpen(
                        .repository(repositoryStableKey: repository.stableKey)
                    ),
                    hasChildren: true,
                    showsActionsButton: true,
                    accessibilityLabel: [
                        repository.name,
                        defaultWorktree.name,
                        defaultWorktree.path.path,
                    ].joined(separator: ", "),
                    accessibilityHint: "Open terminal; show repository actions with Tab"
                )

                let linkedWorktreeItems = repository.worktrees
                    .filter { $0.id != defaultWorktree.id }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    .map { worktree in
                        let presence =
                            presenceByWorktreeID[worktree.id]
                            ?? emptyWorktreePresence(worktree: worktree, repo: repository)
                        return unifiedWorktreeItem(
                            worktree: worktree,
                            repo: repository,
                            presence: presence,
                            group: Group.repositoriesAndWorktrees,
                            groupPriority: Priority.repositoriesAndWorktrees
                        )
                        .projected(
                            group: Group.repositoriesAndWorktrees,
                            groupPriority: Priority.repositoriesAndWorktrees,
                            action: .quickOpen(
                                .worktree(worktreeStableKey: worktree.stableKey)
                            ),
                            hasChildren: true,
                            showsActionsButton: true,
                            accessibilityLabel: [
                                worktree.name,
                                repository.name,
                                worktree.path.path,
                            ].joined(separator: ", "),
                            accessibilityHint: "Open terminal; show worktree actions with Tab"
                        )
                    }
                return [repositoryItem] + linkedWorktreeItems
            }
    }

    static func projectQuickOpenLocations(
        canonicalItems: [CommandBarItem],
        store: WorkspaceStore,
        focusedPane: WorkspaceFocusedPane?
    ) -> [CommandBarItem] {
        let canonicalByID = Dictionary(uniqueKeysWithValues: canonicalItems.map { ($0.id, $0) })
        var promotedIDs: Set<String> = []
        var promotedPathKeys: Set<String> = []
        var currentRows: [CommandBarItem] = []

        if let worktree = quickOpenCurrentWorktree(store: store, focusedPane: focusedPane),
            let repository = store.repositoryTopologyAtom.repo(containing: worktree.id),
            let canonicalID = quickOpenCanonicalID(worktree: worktree, repository: repository),
            let item = canonicalByID[canonicalID]
        {
            currentRows.append(
                item.projected(
                    group: Group.current,
                    groupPriority: Priority.current
                )
            )
            promotedIDs.insert(canonicalID)
            promotedPathKeys.insert(quickOpenPathKey(worktree.path))
        } else if let focusedPane,
            let cwd = store.paneAtom.pane(focusedPane.paneId)?.metadata.cwd
        {
            appendCurrentDirectory(
                cwd,
                detail: nil,
                rows: &currentRows,
                promotedPathKeys: &promotedPathKeys
            )
        }

        if let watchedRoot = store.repositoryTopologyAtom.watchedPaths.first?.path {
            let watchedPathKey = quickOpenPathKey(watchedRoot)
            if !promotedPathKeys.contains(watchedPathKey),
                let canonicalItem = canonicalItems.first(where: { item in
                    quickOpenPath(for: item, store: store).map(quickOpenPathKey) == watchedPathKey
                })
            {
                currentRows.append(
                    canonicalItem.projected(
                        group: Group.current,
                        groupPriority: Priority.current
                    )
                )
                promotedIDs.insert(canonicalItem.id)
                promotedPathKeys.insert(watchedPathKey)
            } else {
                appendCurrentDirectory(
                    watchedRoot,
                    detail: "Watched folder",
                    rows: &currentRows,
                    promotedPathKeys: &promotedPathKeys
                )
            }
        }
        appendCurrentDirectory(
            FileManager.default.homeDirectoryForCurrentUser,
            detail: "Home folder",
            rows: &currentRows,
            promotedPathKeys: &promotedPathKeys
        )

        var recentRows: [CommandBarItem] = []
        for recency in atom(\.applicationEntityRecency).recentEntities {
            guard recentRows.count < 5 else { break }
            guard
                let canonicalID = quickOpenCanonicalID(
                    for: recency.entity,
                    store: store
                ),
                !promotedIDs.contains(canonicalID),
                let item = canonicalByID[canonicalID],
                let path = quickOpenPath(
                    for: recency.entity,
                    store: store
                ),
                !promotedPathKeys.contains(quickOpenPathKey(path))
            else {
                continue
            }
            promotedIDs.insert(canonicalID)
            promotedPathKeys.insert(quickOpenPathKey(path))
            recentRows.append(
                item.projected(
                    group: Group.recent,
                    groupPriority: Priority.recent
                )
            )
        }

        return currentRows
            + recentRows
            + canonicalItems.filter { item in
                guard !promotedIDs.contains(item.id) else { return false }
                guard let path = quickOpenPath(for: item, store: store) else { return true }
                return !promotedPathKeys.contains(quickOpenPathKey(path))
            }
    }

    static func quickOpenDefaultWorktree(for repository: Repo) -> Worktree? {
        repository.worktrees.first(where: \.isMainWorktree)
            ?? repository.worktrees.first
    }

    private static func quickOpenCurrentWorktree(
        store: WorkspaceStore,
        focusedPane: WorkspaceFocusedPane?
    ) -> Worktree? {
        if let worktreeID = focusedPane?.worktreeId,
            let worktree = store.repositoryTopologyAtom.worktree(worktreeID)
        {
            return worktree
        }
        return nil
    }

    private static func appendCurrentDirectory(
        _ directory: URL,
        detail: String?,
        rows: inout [CommandBarItem],
        promotedPathKeys: inout Set<String>
    ) {
        let normalizedDirectory = directory.standardizedFileURL
        let pathKey = quickOpenPathKey(normalizedDirectory)
        guard promotedPathKeys.insert(pathKey).inserted else { return }
        rows.append(
            quickOpenDirectoryItem(
                normalizedDirectory,
                detail: detail,
                group: Group.current,
                groupPriority: Priority.current
            )
        )
    }

    private static func quickOpenDirectoryItem(
        _ directory: URL,
        detail: String?,
        group: String,
        groupPriority: Int
    ) -> CommandBarItem {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let isHome = quickOpenPathKey(directory) == quickOpenPathKey(home)
        let title = isHome ? "~" : directory.lastPathComponent
        let displayPath =
            isHome
            ? "~"
            : directory.path.replacingOccurrences(
                of: home.path + "/",
                with: "~/",
                options: [.anchored]
            )
        return CommandBarItem(
            id: "directory-\(StableKey.fromPath(directory))",
            title: title.isEmpty ? displayPath : title,
            subtitle: displayPath,
            secondaryLine: detail.map {
                CommandBarItemSecondaryLine(text: $0, icon: nil)
            },
            icon: .system(.folder),
            group: group,
            groupPriority: groupPriority,
            keywords: ["directory", "folder", title, directory.path],
            action: .quickOpen(.directory(directory)),
            accessibilityHint: "Open terminal in directory"
        )
    }

    private static func quickOpenPath(
        for entity: ApplicationRecentEntity,
        store: WorkspaceStore
    ) -> URL? {
        switch entity {
        case .repository(let repositoryStableKey):
            guard
                let repository = store.repositoryTopologyAtom.repo(stableKey: repositoryStableKey)
            else {
                return nil
            }
            return quickOpenDefaultWorktree(for: repository)?.path
        case .worktree(let worktreeStableKey):
            return store.repositoryTopologyAtom.worktree(stableKey: worktreeStableKey)?.path
        }
    }

    private static func quickOpenPath(
        for item: CommandBarItem,
        store: WorkspaceStore
    ) -> URL? {
        guard case .quickOpen(let target) = item.action else { return nil }
        switch target {
        case .repository(let repositoryStableKey):
            guard
                let repository = store.repositoryTopologyAtom.repo(stableKey: repositoryStableKey)
            else {
                return nil
            }
            return quickOpenDefaultWorktree(for: repository)?.path
        case .worktree(let worktreeStableKey):
            return store.repositoryTopologyAtom.worktree(stableKey: worktreeStableKey)?.path
        case .directory(let directory):
            return directory
        }
    }

    private static func quickOpenPathKey(_ path: URL) -> String {
        path.standardizedFileURL.path
    }

    private static func quickOpenCanonicalID(
        for entity: ApplicationRecentEntity,
        store: WorkspaceStore
    ) -> String? {
        switch entity {
        case .repository(let repositoryStableKey):
            guard
                let repository = store.repositoryTopologyAtom.repo(stableKey: repositoryStableKey),
                !store.repositoryTopologyAtom.isRepoUnavailable(repository.id),
                quickOpenDefaultWorktree(for: repository) != nil
            else {
                return nil
            }
            return "repo-\(repository.id.uuidString)"
        case .worktree(let worktreeStableKey):
            guard
                let worktree = store.repositoryTopologyAtom.worktree(stableKey: worktreeStableKey),
                let repository = store.repositoryTopologyAtom.repo(containing: worktree.id),
                !store.repositoryTopologyAtom.isRepoUnavailable(repository.id)
            else {
                return nil
            }
            return quickOpenCanonicalID(worktree: worktree, repository: repository)
        }
    }

    private static func quickOpenCanonicalID(
        worktree: Worktree,
        repository: Repo
    ) -> String? {
        guard let defaultWorktree = quickOpenDefaultWorktree(for: repository) else {
            return nil
        }
        return worktree.id == defaultWorktree.id
            ? "repo-\(repository.id.uuidString)"
            : "repo-wt-\(worktree.id.uuidString)"
    }
}
