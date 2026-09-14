import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite("Repository retention pipeline", .serialized)
struct RepositoryRetentionPipelineTests {
    enum Scan: CaseIterable, Sendable { case absent, partial, returned, ownedNeighbor }

    @Test(
        "expiry requires applied authoritative absence; partial scans and returns retain identity",
        arguments: Scan.allCases)
    func expiryUsesAppliedScanEvidence(_ scan: Scan) async throws {
        try await withAsyncTestCoreAtoms { _ in
            let root = FileManager.default.temporaryDirectory.appending(path: "retention-pipeline-\(UUIDv7.generate())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let datastore = WorkspaceSQLiteDatastoreFactory(
                coreDatabaseURL: root.appending(path: "core.sqlite"),
                localDatabaseURL: root.appending(path: "local.sqlite")
            ).makeDatastore()
            guard case .prepared = await datastore.prepareDatabasesForBoot() else {
                Issue.record("expected prepared databases")
                return
            }
            let store = WorkspaceStore()
            let watched = try #require(store.mutationCoordinator.addWatchedPath(root))
            let repository = store.addRepo(at: root.appending(path: "repository"))
            let originalTime = try await RepositoryRetentionTime.current()
            #expect(store.mutationCoordinator.recordRepositoryAbsence(repository.id, at: originalTime))
            let ownedRepository: Repo?
            if scan == .ownedNeighbor {
                let owned = store.addRepo(at: root.appending(path: "owned"))
                #expect(store.mutationCoordinator.recordRepositoryAbsence(owned.id, at: originalTime))
                _ = try await datastore.commitRepositoryLocalActivity(
                    .init(
                        repositoryUpdates: [
                            .init(
                                repositoryStableKey: owned.stableKey, coverageChange: .restart(at: originalTime.utc),
                                ownedPromotionChange: .begin(attemptID: UUIDv7.generate(), startedAt: originalTime.utc))
                        ], updatedAt: originalTime.utc))
                ownedRepository = owned
            } else {
                ownedRepository = nil
            }
            let persistence = RepositoryTopologyStore(atom: store.repositoryTopologyAtom, sqliteDatastore: datastore)
            try await persistence.flushAsync()
            if case .loaded(let persisted) = await datastore.loadRepositoryTopologySnapshot() {
                #expect(persisted.absenceRecords == store.repositoryTopologyAtom.absenceRecords)
            }
            let bus = EventBus<RuntimeEnvelope>()
            let scans = ControllableWatchedFolderScanSchedulerResults()
            scans.setResults(
                [watched: scan == .returned ? [.init(clonePath: repository.repoPath, linkedWorktreePaths: [])] : []],
                partial: scan == .partial)
            let filesystem = FilesystemActor(
                bus: bus, fseventStreamClient: ControllableFSEventStreamClient(),
                watchedFolderScanScheduler: scans.makeScheduler())
            let coordinator = WorkspaceCacheCoordinator(
                bus: bus, workspaceStore: store, repoCache: RepoCacheAtom(), topologyPersistence: persistence,
                retentionNow: {
                    .init(
                        utc: originalTime.utc, bootID: originalTime.bootID,
                        uptimeNanoseconds: originalTime.uptimeNanoseconds + 30 * 86_400 * 1_000_000_000)
                },
                refreshRetentionScopes: { paths, repositories, revision, scopeIDs in
                    _ = await filesystem.refreshWatchedFolders(
                        paths, restoring: repositories, membershipRevision: revision, scanning: scopeIDs)
                    return await filesystem.currentWatchedFolderObservationReceipts()
                },
                validateSourceObservations: { await filesystem.areCurrentWatchedFolderObservations($0) },
                scopeSyncHandler: { change in
                    switch change {
                    case .updateRepositoryScanBaseline(let repositories, let revision):
                        await filesystem.updateRepositoryScanBaseline(repositories, membershipRevision: revision)
                    case .updateWatchedFolders(let paths, let repos, let revision):
                        _ = await filesystem.refreshWatchedFolders(
                            paths, restoring: repos, membershipRevision: revision)
                    case .registerForgeRepo, .unregisterForgeRepo, .refreshForgeRepo: break
                    }
                }
            )
            await coordinator.startConsuming()

            await coordinator.collectRetainedRepositories()

            switch scan {
            case .absent, .ownedNeighbor:
                #expect(store.repositoryTopologyAtom.repo(repository.id) == nil)
                guard case .loaded(let snapshot) = await datastore.loadRepositoryTopologySnapshot() else {
                    Issue.record("expected committed topology")
                    await coordinator.shutdown()
                    await filesystem.shutdown()
                    return
                }
                #expect(snapshot.repos.map(\.id) == ownedRepository.map { [$0.id] } ?? [])
                #expect(snapshot.worktrees.map(\.id) == ownedRepository?.worktrees.map(\.id) ?? [])
            case .partial:
                #expect(store.repositoryTopologyAtom.repo(repository.id) != nil)
                #expect(store.repositoryTopologyAtom.isRepoUnavailable(repository.id))
            case .returned:
                #expect(
                    store.repositoryTopologyAtom.repo(repository.id)?.worktrees.map(\.id)
                        == repository.worktrees.map(\.id))
                #expect(!store.repositoryTopologyAtom.isRepoUnavailable(repository.id))
            }
            await coordinator.shutdown()
            await filesystem.shutdown()
        }
    }
}
