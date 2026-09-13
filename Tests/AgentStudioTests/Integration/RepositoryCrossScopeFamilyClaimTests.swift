import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite("Repository cross-scope family claims", .serialized)
struct RepositoryCrossScopeFamilyClaimTests {
    @Test("conflicting current family claims defer reparenting until covering sources agree")
    func currentFamilyConflictDefersReparenting() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let root = FileManager.default.temporaryDirectory.appending(
                path: "cross-scope-family-\(UUIDv7.generate())")
            let nestedRoot = root.appending(path: "nested")
            let firstFamilyPath = nestedRoot.appending(path: "first-family")
            let secondFamilyPath = nestedRoot.appending(path: "second-family")
            let checkoutPath = nestedRoot.appending(path: "checkout")
            for path in [firstFamilyPath, secondFamilyPath, checkoutPath] {
                try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            }
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
            let outer = try #require(store.mutationCoordinator.addWatchedPath(root))
            let inner = try #require(store.mutationCoordinator.addWatchedPath(nestedRoot))
            let firstFamily = store.addRepo(at: firstFamilyPath)
            let checkout = Worktree(
                id: UUIDv7.generate(), repoId: firstFamily.id, name: "checkout", path: checkoutPath, note: "retain me")
            _ = store.mutationCoordinator.reconcileDiscoveredWorktrees(
                firstFamily.id, worktrees: firstFamily.worktrees + [checkout])
            let persistence = RepositoryTopologyStore(atom: store.repositoryTopologyAtom, sqliteDatastore: datastore)
            try await persistence.flushAsync()
            let originalGroups = [
                RepoScanner.RepoScanGroup(clonePath: firstFamilyPath, linkedWorktreePaths: [checkoutPath])
            ]
            let changedGroups = [
                RepoScanner.RepoScanGroup(clonePath: firstFamilyPath, linkedWorktreePaths: []),
                RepoScanner.RepoScanGroup(clonePath: secondFamilyPath, linkedWorktreePaths: [checkoutPath]),
            ]
            let scans = ControllableWatchedFolderScanSchedulerResults()
            scans.setResults([outer: originalGroups, inner: originalGroups])
            let filesystem = FilesystemActor(
                bus: EventBus<RuntimeEnvelope>(), fseventStreamClient: ControllableFSEventStreamClient(),
                watchedFolderScanScheduler: scans.makeScheduler())
            let coordinator = WorkspaceCacheCoordinator(
                workspaceStore: store, repoCache: RepoCacheAtom(), topologyPersistence: persistence,
                validateSourceObservations: { await filesystem.areCurrentWatchedFolderObservations($0) },
                scopeSyncHandler: { change in
                    if case .updateRepositoryScanBaseline(let repositories, let revision) = change {
                        await filesystem.updateRepositoryScanBaseline(repositories, membershipRevision: revision)
                    }
                })
            do {
                _ = await filesystem.refreshWatchedFolders(
                    [outer, inner], restoring: store.repositoryTopologyAtom.repos,
                    membershipRevision: store.repositoryTopologyAtom.worktreePathIndexGeneration)
                let initial = await filesystem.currentWatchedFolderObservationReceipts()
                let first = try #require(initial.min { $0.sequence < $1.sequence })
                let last = try #require(initial.max { $0.sequence < $1.sequence })
                let changedWatch = last.observation.registration.sourceID.rootID == outer.id ? outer : inner
                let unchangedWatch = changedWatch.id == outer.id ? inner : outer
                scans.setResults([unchangedWatch: originalGroups, changedWatch: changedGroups])

                let conflicting = try await scanReceipt(
                    filesystem: filesystem, watch: changedWatch, after: last.sequence)
                #expect(
                    await filesystem.areCurrentWatchedFolderObservations([first.observation, conflicting.observation]))
                await coordinator.consumeWatchedFolderObservation(
                    conflicting.observation, sequence: conflicting.sequence)

                #expect(store.repositoryTopologyAtom.worktree(checkout.id)?.repoId == firstFamily.id)
                guard case .loaded(let persisted) = await datastore.loadRepositoryTopologySnapshot() else {
                    Issue.record("expected persisted topology")
                    await coordinator.shutdown()
                    await filesystem.shutdown()
                    return
                }
                #expect(persisted.worktrees.first { $0.id == checkout.id }?.repoId == firstFamily.id)

                scans.setResults([outer: changedGroups, inner: changedGroups])
                let agreed = try await scanReceipt(
                    filesystem: filesystem, watch: unchangedWatch, after: conflicting.sequence)
                await coordinator.consumeWatchedFolderObservation(agreed.observation, sequence: agreed.sequence)
                let secondFamily = try #require(
                    store.repositoryTopologyAtom.repos.first {
                        $0.repoPath.path == secondFamilyPath.path
                    })
                #expect(store.repositoryTopologyAtom.worktree(checkout.id)?.repoId == secondFamily.id)
                #expect(store.repositoryTopologyAtom.worktree(checkout.id)?.note == "retain me")
            } catch {
                await coordinator.shutdown()
                await filesystem.shutdown()
                throw error
            }
            await coordinator.shutdown()
            await filesystem.shutdown()
        }
    }

    private func scanReceipt(
        filesystem: FilesystemActor, watch: WatchedPath, after sequence: UInt64
    ) async throws -> WatchedFolderTopologyReceipt {
        let registrations = await filesystem.watchedFolderScanState.registrationsBySourceID
        let registration = try #require(registrations.values.first { $0.watchedPath.id == watch.id })
        await filesystem.handleWatchedFolderFSEvent(
            .init(
                worktreeId: registration.legacyCallbackRoutingID, paths: [watch.path.appending(path: ".git/HEAD").path])
        )
        await assertEventuallyAsync("new authoritative source result") {
            await filesystem.currentWatchedFolderObservationReceipts().contains {
                $0.observation.registration.sourceID.rootID == watch.id && $0.sequence > sequence
            }
        }
        let receipts = await filesystem.currentWatchedFolderObservationReceipts()
        return try #require(
            receipts.first {
                $0.observation.registration.sourceID.rootID == watch.id && $0.sequence > sequence
            })
    }
}
