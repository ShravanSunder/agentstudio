import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioRepoExplorer
@testable import AgentStudioTestSupport

@MainActor
@Suite("Real repository discovery lifecycle persistence", .serialized)
struct RepositoryDiscoveryLifecyclePersistenceTests {
    @Test("package discovery reaches visible checkout capture and SQLite, then restores retained identity")
    func realDiscoveryPublishesAndPersistsCheckout() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            // Read-only Git fixture: every normal local/CI invocation runs from an actual checkout.
            // This exercises main clones on CI and linked worktrees in local worktrees without creating Git metadata.
            let checkoutRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
            let databaseRoot = FileManager.default.temporaryDirectory.appending(
                path: "discovery-persistence-\(UUIDv7.generate())")
            try FileManager.default.createDirectory(at: databaseRoot, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: databaseRoot) }
            let datastore = WorkspaceSQLiteDatastoreFactory(
                coreDatabaseURL: databaseRoot.appending(path: "core.sqlite"),
                localDatabaseURL: databaseRoot.appending(path: "local.sqlite")
            ).makeDatastore()
            guard case .prepared = await datastore.prepareDatabasesForBoot() else {
                Issue.record("expected isolated databases")
                return
            }
            let store = WorkspaceStore()
            let watch = try #require(store.mutationCoordinator.addWatchedPath(checkoutRoot))
            let persistence = RepositoryTopologyStore(atom: store.repositoryTopologyAtom, sqliteDatastore: datastore)
            let bus = EventBus<RuntimeEnvelope>()
            // Scanner and Git discovery are production implementations. Only OS watch notifications are replaced.
            let filesystem = FilesystemActor(bus: bus, fseventStreamClient: ControllableFSEventStreamClient())
            let coordinator = WorkspaceCacheCoordinator(
                bus: bus, workspaceStore: store, repoCache: atoms.repoCache, topologyPersistence: persistence,
                validateSourceObservations: { await filesystem.areCurrentWatchedFolderObservations($0) },
                scopeSyncHandler: { change in
                    switch change {
                    case .updateRepositoryScanBaseline(let repositories, let revision):
                        await filesystem.updateRepositoryScanBaseline(repositories, membershipRevision: revision)
                    case .updateWatchedFolders(let paths, let repositories, let revision):
                        _ = await filesystem.refreshWatchedFolders(
                            paths, restoring: repositories, membershipRevision: revision)
                    case .registerForgeRepo, .unregisterForgeRepo, .refreshForgeRepo: break
                    }
                })
            await coordinator.startConsuming()
            do {
                _ = await filesystem.refreshWatchedFolders(
                    [watch], restoring: [], membershipRevision: store.repositoryTopologyAtom.worktreePathIndexGeneration
                )
                await assertEventuallyMain("real discovery publishes an available checkout") {
                    store.repositoryTopologyAtom.repoAndWorktree(containing: checkoutRoot) != nil
                }
                let association = try #require(store.repositoryTopologyAtom.repoAndWorktree(containing: checkoutRoot))
                let repositoryID = association.repo.id
                let worktreeID = association.worktree.id
                let capture = RepoExplorerProjectionInputCapture(
                    store: store, preferences: RepoExplorerSidebarPrefsAtom(), repoCache: atoms.repoCache,
                    sidebarState: atoms.workspaceSidebarState, sidebarCache: atoms.sidebarCache, coreAtoms: atoms,
                    bridgeAttendanceSnapshot: { _ in nil }, latestPaneMessageSnapshot: { _ in nil })
                let initial = capture.captureRequest(query: "", referenceDate: Date(), trigger: .dataRefresh)
                #expect(initial.snapshot.repos.flatMap(\.worktrees).map(\.id) == [worktreeID])
                try await persistence.flushAsync()
                try await expectPersistedCheckout(datastore, repositoryID: repositoryID, worktreeID: worktreeID)

                store.markRepoUnavailable(repositoryID)
                try await persistence.flushAsync()
                #expect(
                    capture.captureRequest(query: "", referenceDate: Date(), trigger: .dataRefresh).snapshot.repos
                        .isEmpty)
                _ = await filesystem.refreshWatchedFolders(
                    [watch], restoring: store.repos,
                    membershipRevision: store.repositoryTopologyAtom.worktreePathIndexGeneration)
                await assertEventuallyMain("fresh package discovery restores the retained checkout") {
                    store.repositoryTopologyAtom.repoAndWorktree(containing: checkoutRoot)?.worktree.id == worktreeID
                }
                try await persistence.flushAsync()
                let restored = capture.captureRequest(query: "", referenceDate: Date(), trigger: .dataRefresh)
                #expect(restored.snapshot.repos.map(\.id) == [repositoryID])
                #expect(restored.snapshot.repos.flatMap(\.worktrees).map(\.id) == [worktreeID])
                try await expectPersistedCheckout(datastore, repositoryID: repositoryID, worktreeID: worktreeID)
                await coordinator.shutdown()
                await filesystem.shutdown()
            } catch {
                await coordinator.shutdown()
                await filesystem.shutdown()
                throw error
            }
        }
    }

    private func expectPersistedCheckout(
        _ datastore: WorkspaceSQLiteDatastoreActor, repositoryID: UUID, worktreeID: UUID
    ) async throws {
        guard case .loaded(let snapshot) = await datastore.loadRepositoryTopologySnapshot() else {
            Issue.record("expected persisted discovery topology")
            return
        }
        #expect(snapshot.repos.map(\.id) == [repositoryID])
        #expect(snapshot.worktrees.map(\.id) == [worktreeID])
        #expect(snapshot.worktrees.first?.repoId == repositoryID)
        #expect(snapshot.absenceRecords.repositories.isEmpty)
        #expect(snapshot.absenceRecords.worktrees.isEmpty)
    }
}
