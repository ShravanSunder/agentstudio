import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@MainActor
@Suite("Repository retention datastore", .serialized)
struct RepositoryRetentionDatastoreTests {
    @Test("core collection fences delayed local snapshots and restart cleanup converges")
    func collectionFencesStaleLocalSnapshots() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "retention-databases-\(UUIDv7.generate())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let coreURL = root.appending(path: "core.sqlite")
        let localURL = root.appending(path: "local.sqlite")
        let datastore = WorkspaceSQLiteDatastoreFactory(coreDatabaseURL: coreURL, localDatabaseURL: localURL)
            .makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("expected fixture databases")
            return
        }
        try await datastore.saveWorkspaceSnapshotBundle(.emptyTopologyFixture(workspace: .init(id: UUIDv7.generate())))
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repo = coordinator.addRepo(at: root.appending(path: "repository"))
        let main = try #require(repo.worktrees.first)
        let store = RepositoryTopologyStore(atom: atom, sqliteDatastore: datastore)
        let start = RepositoryRetentionTime(
            utc: Date(timeIntervalSince1970: 1_700_000_000), bootID: "fixture", uptimeNanoseconds: 1)
        #expect(coordinator.recordRepositoryAbsence(repo.id, at: start))
        try await store.flushAsync()
        let staleCache = WorkspaceLocalRepository.CacheStateRecord(
            repoEnrichmentByRepoId: [repo.id: .awaitingOrigin(repoId: repo.id)],
            worktreeEnrichmentByWorktreeId: [main.id: .init(worktreeId: main.id, repoId: repo.id, branch: "main")],
            sourceRevision: 1, lastRebuiltAt: nil
        )
        let staleRecency = [
            try ApplicationEntityRecency(
                entity: .repository(repositoryStableKey: repo.stableKey), interaction: .opened,
                lastInteractedAt: start.utc
            )
        ]
        try await datastore.saveRepoCacheState(cacheState: staleCache)
        try await datastore.saveApplicationEntityRecency(staleRecency)
        _ = try await datastore.commitRepositoryLocalActivity(
            .init(
                repositoryUpdates: [
                    .init(
                        repositoryStableKey: repo.stableKey, qualifyingActivityAt: start.utc,
                        coverageChange: .restart(at: start.utc))
                ], updatedAt: start.utc
            ))
        let candidates = RepositoryRetentionCandidates(
            repositoryAbsences: atom.absenceRecords.repositories, worktreeAbsences: atom.absenceRecords.worktrees
        )
        let due = RepositoryRetentionTime(
            utc: start.utc, bootID: start.bootID, uptimeNanoseconds: 30 * 86_400 * 1_000_000_000 + 1)

        let committed = try await store.collect(candidates, expectedRevision: atom.lifecycleRevision, at: due)
        #expect(coordinator.applyRepositoryLifecycleChange(committed))
        guard case .loaded(let recencyBeforeCleanup) = await datastore.loadApplicationEntityRecency(),
            case .loaded(let activityBeforeCleanup) = await datastore.loadRepositoryLocalActivity()
        else {
            Issue.record("expected local state while cleanup is pending")
            return
        }
        #expect(recencyBeforeCleanup.isEmpty)
        #expect(activityBeforeCleanup.activityByRepositoryStableKey.isEmpty)
        try await datastore.saveRepoCacheState(cacheState: staleCache)
        try await datastore.saveApplicationEntityRecency(staleRecency)

        guard case .loaded(let cache) = await datastore.loadRepoCacheState() else {
            Issue.record("expected local cache readback")
            return
        }
        #expect(cache.repoEnrichmentByRepoId.isEmpty)
        #expect(cache.worktreeEnrichmentByWorktreeId.isEmpty)
        let reopened = WorkspaceSQLiteDatastoreFactory(coreDatabaseURL: coreURL, localDatabaseURL: localURL)
            .makeDatastore()
        guard case .prepared = await reopened.prepareDatabasesForBoot() else {
            Issue.record("expected reopened fixture databases")
            return
        }
        #expect(await reopened.reconcileRepositoryLocalOrphans() == .progress)
        #expect(await reopened.reconcileRepositoryLocalOrphans() == .complete)
        guard case .loaded(let topology) = await reopened.loadRepositoryTopologySnapshot() else {
            Issue.record("expected committed core state")
            return
        }
        #expect(topology.repos.isEmpty)
        #expect(topology.worktrees.isEmpty)
    }
}
