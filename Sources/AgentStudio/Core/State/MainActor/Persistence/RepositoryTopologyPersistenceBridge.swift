import Foundation

@MainActor
enum RepositoryTopologyPersistenceBridge {
    struct RuntimeTopologyProjection {
        var repos: [Repo]
        var watchedPaths: [WatchedPath]
        var unavailableRepoIds: Set<UUID>
    }

    static func runtimeTopology(
        from topology: WorkspaceCoreRepository.RepositoryTopologyRecord
    ) -> RuntimeTopologyProjection {
        .init(
            repos: repos(from: topology),
            watchedPaths: topology.watchedPaths.map(watchedPath),
            unavailableRepoIds: topology.unavailableRepoIds
        )
    }

    static func hydrate(
        _ state: WorkspacePersistor.PersistableState,
        identityAtom: WorkspaceIdentityAtom,
        windowMemoryAtom: WorkspaceWindowMemoryAtom,
        repositoryTopologyStore: RepositoryTopologyStore,
        workspacePaneAtom: WorkspacePaneAtom,
        workspaceTabLayoutAtom: WorkspaceTabLayoutAtom
    ) -> WorkspaceTabMembershipRepairReport {
        WorkspacePersistenceTransformer.hydrate(
            state,
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: repositoryTopologyStore.repositoryTopologyAtom,
            workspacePaneAtom: workspacePaneAtom,
            workspaceTabLayoutAtom: workspaceTabLayoutAtom
        )
    }

    static func makeLiveSQLiteSnapshotResult(
        identityAtom: WorkspaceIdentityAtom,
        windowMemoryAtom: WorkspaceWindowMemoryAtom,
        repositoryTopologyStore: RepositoryTopologyStore,
        workspacePaneAtom: WorkspacePaneAtom,
        workspaceTabLayoutAtom: WorkspaceTabLayoutAtom,
        persistedAt: Date
    ) -> WorkspaceLiveSQLiteSnapshotResult {
        WorkspacePersistenceTransformer.makeLiveSQLiteSnapshotResult(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: repositoryTopologyStore.repositoryTopologyAtom,
            workspacePaneAtom: workspacePaneAtom,
            workspaceTabLayoutAtom: workspaceTabLayoutAtom,
            persistedAt: persistedAt
        )
    }

    static func makePersistableState(
        identityAtom: WorkspaceIdentityAtom,
        windowMemoryAtom: WorkspaceWindowMemoryAtom,
        repositoryTopologyStore: RepositoryTopologyStore,
        workspacePaneAtom: WorkspacePaneAtom,
        workspaceTabLayoutAtom: WorkspaceTabLayoutAtom,
        persistedAt: Date
    ) -> WorkspacePersistor.PersistableState {
        WorkspacePersistenceTransformer.makePersistableState(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: repositoryTopologyStore.repositoryTopologyAtom,
            workspacePaneAtom: workspacePaneAtom,
            workspaceTabLayoutAtom: workspaceTabLayoutAtom,
            persistedAt: persistedAt
        )
    }

    private static func repos(from topology: WorkspaceCoreRepository.RepositoryTopologyRecord) -> [Repo] {
        topology.repos.map { repo in
            Repo(
                id: repo.id,
                name: repo.name,
                repoPath: repo.repoPath,
                worktrees: repo.worktrees.map(worktree),
                createdAt: repo.createdAt
            )
        }
    }

    private static func worktree(from record: WorkspaceCoreRepository.WorktreeRecord) -> Worktree {
        Worktree(
            id: record.id,
            repoId: record.repoId,
            name: record.name,
            path: record.path,
            isMainWorktree: record.isMainWorktree
        )
    }

    private static func watchedPath(from record: WorkspaceCoreRepository.WatchedPathRecord) -> WatchedPath {
        WatchedPath(id: record.id, path: record.path, addedAt: record.addedAt)
    }
}
