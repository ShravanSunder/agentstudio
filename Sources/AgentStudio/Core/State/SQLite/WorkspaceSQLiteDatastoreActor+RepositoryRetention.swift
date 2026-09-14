import AgentStudioInfrastructure
import Foundation

extension WorkspaceSQLiteDatastoreActor {
    func unsettledRepositoryRetentionKeys() throws -> Set<String> {
        try preparedApplicationLocalRepository().unsettledRepositoryRetentionKeys()
    }

    func survivingRepositoryRetentionIdentity() throws -> RepositoryRetentionSurvivingIdentity {
        survivingRepositoryRetentionIdentity(from: try journalRepository().fetchRepositoryTopology())
    }

    func survivingRepositoryRetentionIdentity(
        from topology: WorkspaceCoreRepository.RepositoryTopologyRecord
    ) -> RepositoryRetentionSurvivingIdentity {
        .init(
            repositoryIDs: Set(topology.repos.map(\.id)),
            worktreeIDs: Set(topology.repos.flatMap(\.worktrees).map(\.id)),
            repositoryKeys: Set(topology.repos.map(\.stableKey)),
            worktreeKeys: Set(topology.repos.flatMap(\.worktrees).map(\.stableKey)),
            worktreeRepositoryIDs: Dictionary(
                uniqueKeysWithValues: topology.repos.flatMap(\.worktrees).map { ($0.id, $0.repoId) })
        )
    }

    /// Called before loading local caches and after collection; crashes between databases need no deletion journal.
    package func reconcileRepositoryLocalOrphans() async -> RepositoryRetentionLocalCleanupResult {
        do {
            let surviving = try survivingRepositoryRetentionIdentity()
            let local = try preparedApplicationLocalRepository()
            retentionSurvivingIdentity = surviving
            let removed = try local.pruneOrphanedRepositoryState(
                surviving: surviving, limit: AppPolicies.RepositoryRetention.collectionBatchLimit
            )
            repositoryLocalCleanupPending = removed != 0
            return removed == 0 ? .complete : .progress
        } catch {
            repositoryLocalCleanupPending = true
            return .unavailable
        }
    }

    func collectRetainedRepositoryLocations(
        _ candidates: RepositoryRetentionCandidates,
        expectedRevision: UInt64,
        at time: RepositoryRetentionTime
    ) async throws -> RepositoryTopologySQLiteSnapshot {
        try await withWorkspacePersistenceOrder(cancelBeforeAdmission: true) { datastore in
            guard datastore.acceptedRepositoryTopologyCaptureRevision == expectedRevision else {
                throw RepositoryRetentionCollectionError.staleTopology
            }
            let core = try datastore.journalRepository()
            let topology = try core.fetchRepositoryTopology()
            let unsettled = try datastore.preparedApplicationLocalRepository().unsettledRepositoryRetentionKeys()
            let blockedRepositories = Set(topology.repos.filter { unsettled.contains($0.stableKey) }.map(\.id))
            guard !candidates.repositoryAbsences.keys.contains(where: blockedRepositories.contains),
                !topology.repos.filter({ blockedRepositories.contains($0.id) }).flatMap(\.worktrees)
                    .contains(where: { candidates.worktreeAbsences[$0.id] != nil })
            else { throw RepositoryRetentionCollectionError.noLongerEligible }
            let committed = try core.collectRetainedRepositoryLocations(candidates, at: time)
            datastore.acceptedRepositoryTopologyCaptureRevision = expectedRevision + 1
            datastore.retentionSurvivingIdentity = datastore.survivingRepositoryRetentionIdentity(from: committed)
            datastore.repositoryLocalCleanupPending = true
            return WorkspaceSQLiteStateBridge.repositoryTopologySnapshot(topology: committed, updatedAt: time.utc)
        }
    }

    func filterRetiredCacheState(_ cache: WorkspaceLocalRepository.CacheStateRecord)
        -> WorkspaceLocalRepository.CacheStateRecord
    {
        guard let surviving = retentionSurvivingIdentity else { return cache }
        return cache.retaining(surviving)
    }
}
