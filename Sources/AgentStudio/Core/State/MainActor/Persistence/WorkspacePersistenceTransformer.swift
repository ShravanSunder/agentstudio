import Foundation
import os.log

private let workspacePersistenceTransformerLogger = Logger(
    subsystem: "com.agentstudio",
    category: "WorkspacePersistenceTransformer"
)

@MainActor
enum WorkspacePersistenceTransformer {
    static func hydrateRepositoryTopology(
        _ snapshot: RepositoryTopologySQLiteSnapshot,
        repositoryTopologyAtom: RepositoryTopologyAtom
    ) {
        guard
            let replacement = preparedTopologyReplacement(
                canonicalRepos: snapshot.repos,
                canonicalWorktrees: snapshot.worktrees,
                watchedPaths: snapshot.watchedPaths,
                unavailableRepositoryIDs: snapshot.unavailableRepoIds
            )
        else {
            workspacePersistenceTransformerLogger.error(
                "Rejected invalid repository topology snapshot before hydration"
            )
            return
        }
        repositoryTopologyAtom.replaceTopology(replacement)
    }

    static func makeRepositoryTopologySQLiteSnapshot(
        identityAtom: WorkspaceIdentityAtom,
        repositoryTopologyAtom: RepositoryTopologyAtom,
        persistedAt: Date
    ) -> RepositoryTopologySQLiteSnapshot {
        RepositoryTopologySQLiteSnapshot(
            id: identityAtom.workspaceId,
            repos: canonicalRepos(from: repositoryTopologyAtom.repos),
            worktrees: canonicalWorktrees(from: repositoryTopologyAtom.repos),
            unavailableRepoIds: repositoryTopologyAtom.unavailableRepoIds,
            watchedPaths: repositoryTopologyAtom.watchedPaths,
            updatedAt: persistedAt
        )
    }

    nonisolated static func sqliteSnapshot(
        from state: WorkspacePersistor.PersistableState
    ) -> WorkspaceSQLiteSnapshot {
        WorkspaceSQLiteSnapshot(
            id: state.id,
            name: state.name,
            panes: state.panes,
            tabs: state.tabs,
            activeTabId: state.activeTabId,
            sidebarWidth: state.sidebarWidth,
            windowFrame: state.windowFrame,
            createdAt: state.createdAt,
            updatedAt: state.updatedAt
        )
    }

    nonisolated static func repositoryTopologySQLiteSnapshot(
        from state: WorkspacePersistor.PersistableState
    ) -> RepositoryTopologySQLiteSnapshot {
        RepositoryTopologySQLiteSnapshot(
            id: state.id,
            repos: state.repos,
            worktrees: state.worktrees,
            unavailableRepoIds: state.unavailableRepoIds,
            watchedPaths: state.watchedPaths,
            updatedAt: state.updatedAt
        )
    }

    nonisolated static func sqliteSaveBundle(
        from state: WorkspacePersistor.PersistableState
    ) -> WorkspaceSQLiteSaveBundle {
        WorkspaceSQLiteSaveBundle(
            workspace: sqliteSnapshot(from: state),
            repositoryTopology: repositoryTopologySQLiteSnapshot(from: state)
        )
    }

    nonisolated static func persistableState(
        from snapshot: WorkspaceSQLiteSnapshot
    ) -> WorkspacePersistor.PersistableState {
        WorkspacePersistor.PersistableState(
            id: snapshot.id,
            name: snapshot.name,
            repos: [],
            worktrees: [],
            unavailableRepoIds: [],
            panes: snapshot.panes,
            tabs: snapshot.tabs,
            activeTabId: snapshot.activeTabId,
            sidebarWidth: snapshot.sidebarWidth,
            windowFrame: snapshot.windowFrame,
            watchedPaths: [],
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt
        )
    }

    nonisolated static func persistableState(
        from bundle: WorkspaceSQLiteSaveBundle
    ) -> WorkspacePersistor.PersistableState {
        let snapshot = bundle.workspace
        let topology = bundle.repositoryTopology
        return WorkspacePersistor.PersistableState(
            id: snapshot.id,
            name: snapshot.name,
            repos: topology.repos,
            worktrees: topology.worktrees,
            unavailableRepoIds: topology.unavailableRepoIds,
            panes: snapshot.panes,
            tabs: snapshot.tabs,
            activeTabId: snapshot.activeTabId,
            sidebarWidth: snapshot.sidebarWidth,
            windowFrame: snapshot.windowFrame,
            watchedPaths: topology.watchedPaths,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt
        )
    }

    private static func canonicalRepos(from repos: [Repo]) -> [CanonicalRepo] {
        repos.map { repo in
            CanonicalRepo(
                id: repo.id,
                name: repo.name,
                repoPath: repo.repoPath,
                createdAt: repo.createdAt,
                tags: repo.tags
            )
        }
    }

    private static func canonicalWorktrees(from repos: [Repo]) -> [CanonicalWorktree] {
        repos.flatMap { repo in
            repo.worktrees.map { worktree in
                CanonicalWorktree(
                    id: worktree.id,
                    repoId: repo.id,
                    name: worktree.name,
                    path: worktree.path,
                    isMainWorktree: worktree.isMainWorktree,
                    tags: worktree.tags
                )
            }
        }
    }

    private static func runtimeRepos(
        canonicalRepos: [CanonicalRepo],
        canonicalWorktrees: [CanonicalWorktree]
    ) -> [Repo] {
        let worktreesByRepoId = Dictionary(grouping: canonicalWorktrees, by: \.repoId)
        return canonicalRepos.map { canonicalRepo in
            let worktrees = (worktreesByRepoId[canonicalRepo.id] ?? []).map { canonicalWorktree in
                Worktree(
                    id: canonicalWorktree.id,
                    repoId: canonicalRepo.id,
                    name: canonicalWorktree.name,
                    path: canonicalWorktree.path,
                    isMainWorktree: canonicalWorktree.isMainWorktree,
                    tags: canonicalWorktree.tags
                )
            }
            return Repo(
                id: canonicalRepo.id,
                name: canonicalRepo.name,
                repoPath: canonicalRepo.repoPath,
                worktrees: worktrees,
                createdAt: canonicalRepo.createdAt,
                tags: canonicalRepo.tags
            )
        }
    }

    private static func preparedTopologyReplacement(
        canonicalRepos: [CanonicalRepo],
        canonicalWorktrees: [CanonicalWorktree],
        watchedPaths: [WatchedPath],
        unavailableRepositoryIDs: Set<UUID>
    ) -> RepositoryTopologyReplacement? {
        switch RepositoryTopologyReplacement.prepare(
            repositories: runtimeRepos(
                canonicalRepos: canonicalRepos,
                canonicalWorktrees: canonicalWorktrees
            ),
            watchedPaths: watchedPaths,
            unavailableRepositoryIDs: unavailableRepositoryIDs
        ) {
        case .prepared(let replacement):
            return replacement
        case .rejected:
            return nil
        }
    }
}
