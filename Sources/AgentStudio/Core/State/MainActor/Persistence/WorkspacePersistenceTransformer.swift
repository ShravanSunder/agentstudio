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

    @concurrent nonisolated static func prepareRepositoryTopologyOffMain(
        _ snapshot: RepositoryTopologySQLiteSnapshot
    ) async -> RepositoryTopologyReplacementPreparation {
        RepositoryTopologyReplacement.prepare(
            repositories: runtimeRepos(
                canonicalRepos: snapshot.repos,
                canonicalWorktrees: snapshot.worktrees
            ),
            watchedPaths: snapshot.watchedPaths,
            unavailableRepositoryIDs: snapshot.unavailableRepoIds
        )
    }

    static func applyPreparedRepositoryTopology(
        _ replacement: RepositoryTopologyReplacement,
        repositoryTopologyAtom: RepositoryTopologyAtom
    ) {
        repositoryTopologyAtom.replaceTopology(replacement)
    }

    @concurrent nonisolated static func makeRepositoryTopologySQLiteSnapshotOffMain(
        repositories: [Repo],
        unavailableRepositoryIDs: Set<UUID>,
        watchedPaths: [WatchedPath],
        persistedAt: Date
    ) async -> RepositoryTopologySQLiteSnapshot {
        RepositoryTopologySQLiteSnapshot(
            repos: canonicalRepos(from: repositories),
            worktrees: canonicalWorktrees(from: repositories),
            unavailableRepoIds: unavailableRepositoryIDs,
            watchedPaths: watchedPaths,
            updatedAt: persistedAt
        )
    }

    private nonisolated static func canonicalRepos(from repos: [Repo]) -> [CanonicalRepo] {
        repos.map { repo in
            CanonicalRepo(
                id: repo.id,
                name: repo.name,
                repoPath: repo.repoPath,
                createdAt: repo.createdAt,
                isFavorite: repo.isFavorite,
                note: repo.note,
                tags: repo.tags
            )
        }
    }

    private nonisolated static func canonicalWorktrees(from repos: [Repo]) -> [CanonicalWorktree] {
        repos.flatMap { repo in
            repo.worktrees.map { worktree in
                CanonicalWorktree(
                    id: worktree.id,
                    repoId: repo.id,
                    name: worktree.name,
                    path: worktree.path,
                    isMainWorktree: worktree.isMainWorktree,
                    note: worktree.note
                )
            }
        }
    }

    private nonisolated static func runtimeRepos(
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
                    note: canonicalWorktree.note
                )
            }
            return Repo(
                id: canonicalRepo.id,
                name: canonicalRepo.name,
                repoPath: canonicalRepo.repoPath,
                worktrees: worktrees,
                createdAt: canonicalRepo.createdAt,
                isFavorite: canonicalRepo.isFavorite,
                note: canonicalRepo.note,
                tags: canonicalRepo.tags
            )
        }
    }

    private nonisolated static func preparedTopologyReplacement(
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
