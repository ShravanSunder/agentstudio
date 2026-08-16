import AgentStudioInfrastructure
import Foundation
import os.log

private let workspacePersistenceTransformerLogger = Logger(
    subsystem: "com.agentstudio",
    category: "WorkspacePersistenceTransformer"
)

struct WorkspaceBootPaneAssociationReconciliation: Sendable {
    let workspace: WorkspaceSQLiteSnapshot
    let summary: PaneAssociationBootReconciliationSummary
}

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
        prepareRepositoryTopology(snapshot)
    }

    @concurrent nonisolated static func reconcilePaneAssociationsOffMain(
        in workspace: WorkspaceSQLiteSnapshot,
        topology: RepositoryTopologyReplacement
    ) async -> WorkspaceBootPaneAssociationReconciliation {
        let topologySnapshot = RepositoryTopologyReadSnapshot(replacement: topology)
        var retainedKnownCount: UInt64 = 0
        var backfilledCount: UInt64 = 0
        var danglingClearedCount: UInt64 = 0
        var freeNilCount: UInt64 = 0
        var changedCount: UInt64 = 0
        var reconciledWorkspace = workspace
        reconciledWorkspace.panes = workspace.panes.map { pane in
            var reconciledPane = pane
            let durableFacets = pane.metadata.facets
            if let repoID = durableFacets.repoId, let worktreeID = durableFacets.worktreeId {
                if topologySnapshot.validatedAssociation(repoId: repoID, worktreeId: worktreeID) != nil {
                    retainedKnownCount += 1
                    return pane
                }
                if topologySnapshot.isKnownAssociationTemporarilyUnavailable(
                    repoId: repoID,
                    worktreeId: worktreeID
                ) {
                    retainedKnownCount += 1
                    return pane
                }
                danglingClearedCount += 1
                changedCount += 1
                reconciledPane.metadata.updateFacets(PaneContextFacets(cwd: durableFacets.cwd))
                return reconciledPane
            }

            guard
                let resolvedContext = topologySnapshot.repoAndWorktree(containing: durableFacets.cwd)
            else {
                freeNilCount += 1
                return pane
            }
            backfilledCount += 1
            changedCount += 1
            reconciledPane.metadata.updateFacets(
                PaneContextFacets(
                    repoId: resolvedContext.repo.id,
                    worktreeId: resolvedContext.worktree.id,
                    cwd: durableFacets.cwd
                )
            )
            return reconciledPane
        }
        return WorkspaceBootPaneAssociationReconciliation(
            workspace: reconciledWorkspace,
            summary: PaneAssociationBootReconciliationSummary(
                paneCount: UInt64(workspace.panes.count),
                retainedKnownCount: retainedKnownCount,
                backfilledCount: backfilledCount,
                danglingClearedCount: danglingClearedCount,
                freeNilCount: freeNilCount,
                changedCount: changedCount
            )
        )
    }

    nonisolated static func prepareRepositoryTopology(
        _ snapshot: RepositoryTopologySQLiteSnapshot
    ) -> RepositoryTopologyReplacementPreparation {
        let normalizedTopology = normalizeRepositoryMainWorktrees(
            repositories: runtimeRepos(
                canonicalRepos: snapshot.repos,
                canonicalWorktrees: snapshot.worktrees
            ),
            unavailableRepositoryIDs: snapshot.unavailableRepoIds
        )
        return RepositoryTopologyReplacement.prepare(
            repositories: normalizedTopology.repositories,
            watchedPaths: snapshot.watchedPaths,
            unavailableRepositoryIDs: normalizedTopology.unavailableRepositoryIDs
        )
    }

    nonisolated static func topologyRestoreReasons(
        _ snapshot: RepositoryTopologySQLiteSnapshot
    ) -> Set<PaneTopologyPersistenceReason> {
        let worktreesByRepositoryID = Dictionary(grouping: snapshot.worktrees, by: \.repoId)
        var reasons = Set<PaneTopologyPersistenceReason>()
        for repository in snapshot.repos {
            let repositoryWorktrees = worktreesByRepositoryID[repository.id] ?? []
            let rootWorktrees = repositoryWorktrees.filter {
                $0.stableKey == repository.stableKey
            }
            guard rootWorktrees.count == 1, let rootWorktree = rootWorktrees.first else {
                reasons.insert(.topologyRestoreMissingMainDegraded)
                if rootWorktrees.count > 1 {
                    reasons.insert(.paneTopologyAssociationAmbiguous)
                }
                continue
            }
            if !rootWorktree.isMainWorktree
                || repositoryWorktrees.contains(where: {
                    $0.id != rootWorktree.id && $0.isMainWorktree
                })
            {
                reasons.insert(.topologyRestoreMainRoleRepaired)
            }
        }
        return reasons
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
        let normalizedTopology = normalizeRepositoryMainWorktrees(
            repositories: runtimeRepos(
                canonicalRepos: canonicalRepos,
                canonicalWorktrees: canonicalWorktrees
            ),
            unavailableRepositoryIDs: unavailableRepositoryIDs
        )
        switch RepositoryTopologyReplacement.prepare(
            repositories: normalizedTopology.repositories,
            watchedPaths: watchedPaths,
            unavailableRepositoryIDs: normalizedTopology.unavailableRepositoryIDs
        ) {
        case .prepared(let replacement):
            return replacement
        case .rejected:
            return nil
        }
    }

    private nonisolated static func normalizeRepositoryMainWorktrees(
        repositories: [Repo],
        unavailableRepositoryIDs: Set<UUID>
    ) -> (repositories: [Repo], unavailableRepositoryIDs: Set<UUID>) {
        var normalizedUnavailableRepositoryIDs = unavailableRepositoryIDs
        let normalizedRepositories = repositories.map { repository in
            let rootWorktreeIndexes = repository.worktrees.indices.filter { index in
                repository.worktrees[index].stableKey == repository.stableKey
            }
            guard rootWorktreeIndexes.count == 1, let rootWorktreeIndex = rootWorktreeIndexes.first else {
                normalizedUnavailableRepositoryIDs.insert(repository.id)
                guard rootWorktreeIndexes.count > 1 else {
                    return repository
                }
                var normalizedRepository = repository
                normalizedRepository.worktrees = repository.worktrees.compactMap { worktree in
                    worktree.stableKey == repository.stableKey ? nil : worktree
                }
                return normalizedRepository
            }

            var normalizedRepository = repository
            normalizedRepository.worktrees = repository.worktrees.enumerated().map { index, worktree in
                var normalizedWorktree = worktree
                normalizedWorktree.isMainWorktree = index == rootWorktreeIndex
                return normalizedWorktree
            }
            return normalizedRepository
        }
        return (normalizedRepositories, normalizedUnavailableRepositoryIDs)
    }
}
