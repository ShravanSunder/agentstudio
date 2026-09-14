import AgentStudioTestSupport
import Foundation
import GRDB
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@MainActor
@Suite("Repository retention commit boundary recovery", .serialized)
struct RepositoryRetentionCommitBoundaryRecoveryTests {
    @Test("cancellation while collection is reserved before core admission releases without deletion")
    func cancellationBeforeCoreAdmissionReleasesReservation() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let persistenceGate = RetentionPersistenceAdmissionGate()
            let fixture = try await makeCoordinatorRetentionFixture(
                name: "precommit-cancellation",
                probe: { event in
                    guard event == .saveWorkspaceSnapshot else { return }
                    await persistenceGate.pauseFirstSave()
                }
            )
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let blockingSave = Task {
                try await fixture.datastore.saveWorkspaceSnapshotBundle(
                    .init(
                        workspace: .init(
                            id: UUIDv7.generate(),
                            name: "persistence admission blocker"
                        )
                    )
                )
            }
            await persistenceGate.waitUntilFirstSavePaused()
            let collection = Task { await fixture.coordinator.collectRetainedRepositories() }
            await assertEventuallyMain("collection owns the reservation before core admission") {
                fixture.coordinator.isCollectingRetainedLocations
            }

            collection.cancel()
            await persistenceGate.releaseFirstSave()
            try await blockingSave.value
            await collection.value

            #expect(!fixture.coordinator.isCollectingRetainedLocations)
            #expect(fixture.store.repositoryTopologyAtom.repo(fixture.repositoryID) != nil)
            guard case .loaded(let topology) = await fixture.datastore.loadRepositoryTopologySnapshot() else {
                Issue.record("expected durable topology readback")
                return
            }
            #expect(topology.repos.map(\.id) == [fixture.repositoryID])
            await fixture.coordinator.shutdown()
        }
    }

    @Test("cancellation after the core commit still publishes the canonical committed result")
    func cancellationAfterCoreCommitPublishesCommittedResult() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let fixture = try await makeCoordinatorRetentionFixture(name: "postcommit-cancellation")
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let commitBarrier = RetentionDeleteCommitBarrier()
            try await fixture.corePool.write { database in
                database.add(transactionObserver: commitBarrier, extent: .observerLifetime)
            }
            commitBarrier.arm()
            let collection = Task { await fixture.coordinator.collectRetainedRepositories() }
            await commitBarrier.waitForDeletionCommit()

            collection.cancel()
            commitBarrier.releaseCommitCallback()
            await collection.value

            #expect(!commitBarrier.didTimeOut)
            #expect(!fixture.coordinator.isCollectingRetainedLocations)
            #expect(fixture.store.repositoryTopologyAtom.repo(fixture.repositoryID) == nil)
            guard case .loaded(let topology) = await fixture.datastore.loadRepositoryTopologySnapshot() else {
                Issue.record("expected committed topology readback")
                return
            }
            #expect(topology.repos.isEmpty)
            #expect(topology.worktrees.isEmpty)
            await fixture.coordinator.shutdown()
        }
    }

    @Test("local unavailability after the core commit converges when local storage returns")
    func localUnavailableAfterCoreCommitRecoversOnReopen() async throws {
        let fixture = try await makeRetentionCommitBoundaryFixture(name: "local-unavailable")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let localRepository = WorkspaceLocalRepository(
            workspaceId: UUIDv7.generate(),
            databaseWriter: fixture.localPool
        )
        try localRepository.replaceCacheState(
            cacheState: .init(
                repoEnrichmentByRepoId: [
                    fixture.repositoryID: .awaitingOrigin(repoId: fixture.repositoryID)
                ],
                worktreeEnrichmentByWorktreeId: [
                    fixture.worktreeID: .init(
                        worktreeId: fixture.worktreeID,
                        repoId: fixture.repositoryID,
                        branch: "main"
                    )
                ],
                sourceRevision: 1,
                lastRebuiltAt: nil
            ),
            updatedAt: fixture.due.utc
        )
        let coreRepository = WorkspaceCoreRepository(databaseWriter: fixture.corePool)
        _ = try coreRepository.collectRetainedRepositoryLocations(fixture.candidates, at: fixture.due)
        let unavailableDatastore = try await preparedWorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            localUnavailable: WorkspaceSQLiteDatastoreFailure(CocoaError(.fileNoSuchFile))
        )

        #expect(await unavailableDatastore.reconcileRepositoryLocalOrphans() == .unavailable)
        #expect(try coreRepository.fetchRepositoryTopology().repos.isEmpty)
        #expect(try localRepository.fetchCacheState().repoEnrichmentByRepoId[fixture.repositoryID] != nil)

        let reopenedDatastore = try await preparedWorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            preparedApplicationLocalRepository: localRepository
        )
        #expect(await reopenedDatastore.reconcileRepositoryLocalOrphans() == .progress)
        #expect(await reopenedDatastore.reconcileRepositoryLocalOrphans() == .complete)
        #expect(try localRepository.fetchCacheState().repoEnrichmentByRepoId.isEmpty)
        #expect(try localRepository.fetchCacheState().worktreeEnrichmentByWorktreeId.isEmpty)
    }
}

@MainActor
private struct RetentionCoordinatorFixture {
    let root: URL
    let corePool: DatabasePool
    let datastore: WorkspaceSQLiteDatastoreActor
    let store: WorkspaceStore
    let coordinator: WorkspaceCacheCoordinator
    let repositoryID: UUID
}

@MainActor
private func makeCoordinatorRetentionFixture(
    name: String,
    probe: (@Sendable (WorkspaceSQLiteDatastoreActor.ProbeEvent) async -> Void)? = nil
) async throws -> RetentionCoordinatorFixture {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "retention-coordinator-boundary-\(name)-\(UUIDv7.generate())"
    )
    let corePool = try SQLiteDatabaseFactory.makeFileBackedPool(
        at: root.appending(path: "core.sqlite"),
        label: "AgentStudio.sqlite.retention-coordinator-boundary.core"
    )
    let localPool = try SQLiteDatabaseFactory.makeFileBackedPool(
        at: root.appending(path: "local.sqlite"),
        label: "AgentStudio.sqlite.retention-coordinator-boundary.local"
    )
    try WorkspaceCoreMigrations.migrate(corePool)
    try WorkspaceLocalMigrations.migrate(localPool)
    let coreRepository = WorkspaceCoreRepository(databaseWriter: corePool)
    let localRepository = WorkspaceLocalRepository(
        workspaceId: UUIDv7.generate(),
        databaseWriter: localPool
    )
    let backend = WorkspaceSQLiteStoreBackend(
        coreRepository: coreRepository,
        makeLocalRepository: { workspaceID in
            WorkspaceLocalRepository(
                workspaceId: workspaceID,
                databaseWriter: localRepository.databaseWriter
            )
        },
        coreDatabaseStartupProvenance: .createdDuringCurrentStartup
    )
    let datastore = try preparedWorkspaceSQLiteDatastore(from: backend, probe: probe)
    let store = WorkspaceStore()
    let watchedRoot = root.appending(path: "watched")
    let watch = try #require(store.mutationCoordinator.addWatchedPath(watchedRoot))
    let repository = store.addRepo(at: watchedRoot.appending(path: "repository"))
    let start = RepositoryRetentionTime(
        utc: Date(timeIntervalSince1970: 1_700_000_000),
        bootID: "fixture",
        uptimeNanoseconds: 1
    )
    #expect(store.mutationCoordinator.recordRepositoryAbsence(repository.id, at: start))
    let persistence = RepositoryTopologyStore(
        atom: store.repositoryTopologyAtom,
        sqliteDatastore: datastore
    )
    try await persistence.flushAsync()
    let due = RepositoryRetentionTime(
        utc: start.utc,
        bootID: start.bootID,
        uptimeNanoseconds: start.uptimeNanoseconds + 30 * 86_400 * 1_000_000_000
    )
    let observation = WatchedFolderTopologyObservation(
        root: watchedRoot,
        registration: .init(
            sourceID: .init(kind: .watchedParentMembership, rootID: watch.id),
            registrationGeneration: 1,
            rootGeneration: 1
        ),
        entries: [],
        otherObservedPaths: [],
        coverage: .authoritative(due),
        baselineMembershipRevision: store.repositoryTopologyAtom.worktreePathIndexGeneration,
        incompleteOtherScopes: []
    )
    let coordinator = WorkspaceCacheCoordinator(
        workspaceStore: store,
        repoCache: RepoCacheAtom(),
        topologyPersistence: persistence,
        retentionNow: { due },
        refreshRetentionScopes: { _, _, _, _ in
            [.init(sequence: 1, observation: observation)]
        },
        validateSourceObservations: { _ in true },
        scopeSyncHandler: { _ in }
    )
    return .init(
        root: root,
        corePool: corePool,
        datastore: datastore,
        store: store,
        coordinator: coordinator,
        repositoryID: repository.id
    )
}

private struct RetentionCommitBoundaryFixture: Sendable {
    let root: URL
    let corePool: DatabasePool
    let localPool: DatabasePool
    let datastore: WorkspaceSQLiteDatastoreActor
    let repositoryID: UUID
    let worktreeID: UUID
    let candidates: RepositoryRetentionCandidates
    let due: RepositoryRetentionTime
}

private func makeRetentionCommitBoundaryFixture(
    name: String
) async throws -> RetentionCommitBoundaryFixture {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "retention-commit-boundary-\(name)-\(UUIDv7.generate())"
    )
    let corePool = try SQLiteDatabaseFactory.makeFileBackedPool(
        at: root.appending(path: "core.sqlite"),
        label: "AgentStudio.sqlite.retention-commit-boundary.core"
    )
    let localPool = try SQLiteDatabaseFactory.makeFileBackedPool(
        at: root.appending(path: "local.sqlite"),
        label: "AgentStudio.sqlite.retention-commit-boundary.local"
    )
    try WorkspaceCoreMigrations.migrate(corePool)
    try WorkspaceLocalMigrations.migrate(localPool)
    let coreRepository = WorkspaceCoreRepository(databaseWriter: corePool)
    let localRepository = WorkspaceLocalRepository(
        workspaceId: UUIDv7.generate(),
        databaseWriter: localPool
    )
    let datastore = try await preparedWorkspaceSQLiteDatastore(
        coreRepository: coreRepository,
        preparedApplicationLocalRepository: localRepository
    )
    let repositoryID = UUIDv7.generate()
    let worktreeID = UUIDv7.generate()
    let repositoryPath = root.appending(path: "repository")
    let start = RepositoryRetentionTime(
        utc: Date(timeIntervalSince1970: 1_700_000_000),
        bootID: "fixture",
        uptimeNanoseconds: 1
    )
    let absence = try #require(RepositoryRetentionPolicy.confirmedAbsence(retaining: nil, at: start))
    let topology = RepositoryTopologySQLiteSnapshot(
        repos: [
            .init(
                id: repositoryID,
                name: "repository",
                repoPath: repositoryPath,
                createdAt: start.utc
            )
        ],
        worktrees: [
            .init(
                id: worktreeID,
                repoId: repositoryID,
                name: "main",
                path: repositoryPath,
                isMainWorktree: true
            )
        ],
        unavailableRepoIds: [repositoryID],
        updatedAt: start.utc,
        absenceRecords: .init(
            repositories: [repositoryID: absence],
            worktrees: [worktreeID: absence]
        )
    )
    try await datastore.saveRepositoryTopologySnapshot(topology, captureRevision: 1)
    let due = RepositoryRetentionTime(
        utc: start.utc,
        bootID: start.bootID,
        uptimeNanoseconds: start.uptimeNanoseconds + 30 * 86_400 * 1_000_000_000
    )
    return .init(
        root: root,
        corePool: corePool,
        localPool: localPool,
        datastore: datastore,
        repositoryID: repositoryID,
        worktreeID: worktreeID,
        candidates: .init(
            repositoryAbsences: [repositoryID: absence],
            worktreeAbsences: [worktreeID: absence]
        ),
        due: due
    )
}

private actor RetentionPersistenceAdmissionGate {
    private var pauseContinuation: CheckedContinuation<Void, Never>?
    private var pausedContinuation: CheckedContinuation<Void, Never>?
    private var didPause = false

    func pauseFirstSave() async {
        guard !didPause else { return }
        didPause = true
        await withCheckedContinuation { continuation in
            pauseContinuation = continuation
            pausedContinuation?.resume()
            pausedContinuation = nil
        }
    }

    func waitUntilFirstSavePaused() async {
        guard !didPause else { return }
        await withCheckedContinuation { continuation in
            pausedContinuation = continuation
        }
    }

    func releaseFirstSave() {
        pauseContinuation?.resume()
        pauseContinuation = nil
    }
}

private final class RetentionDeleteCommitBarrier: TransactionObserver, @unchecked Sendable {
    private static let timeout: DispatchTimeInterval = .seconds(5)

    private let lock = NSLock()
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private var isArmed = false
    private var observedDeletion = false
    private var committed = false
    private var commitContinuation: CheckedContinuation<Void, Never>?
    private var timedOut = false

    var didTimeOut: Bool {
        lock.withLock { timedOut }
    }

    func arm() {
        lock.withLock {
            isArmed = true
        }
    }

    func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        guard case .delete(let tableName) = eventKind else { return false }
        return tableName == "repo" || tableName == "worktree"
    }

    func databaseDidChange(with event: DatabaseEvent) {
        lock.withLock {
            guard isArmed else { return }
            observedDeletion = true
        }
    }

    func databaseDidCommit(_ database: Database) {
        let shouldPause = lock.withLock {
            guard isArmed, observedDeletion else { return false }
            committed = true
            commitContinuation?.resume()
            commitContinuation = nil
            return true
        }
        guard shouldPause else { return }
        if releaseSemaphore.wait(timeout: .now() + Self.timeout) == .timedOut {
            lock.withLock {
                timedOut = true
            }
        }
    }

    func databaseDidRollback(_ database: Database) {
        lock.withLock {
            observedDeletion = false
        }
    }

    func waitForDeletionCommit() async {
        let alreadyCommitted = lock.withLock { committed }
        guard !alreadyCommitted else { return }
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                if committed { return true }
                commitContinuation = continuation
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    func releaseCommitCallback() {
        releaseSemaphore.signal()
    }
}
