import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite("Repository cache save lifetime", .serialized)
struct RepositoryCacheSaveLifetimeTests {
    @Test("a save captured before hide and same-path return cannot overwrite current enrichment")
    func supersededFlushCannotRestorePreHideEnrichment() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let workspaceID = UUIDv7.generate()
            let sqliteFixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
            let firstSaveBarrier = FirstRepoCacheSaveTraceBarrier()
            let traceRuntime = makeTraceRuntime(firstSaveBarrier: firstSaveBarrier)
            var lifecycleCoordinator: WorkspaceCacheCoordinator?
            var obsoleteSave: Task<Void, Error>?
            do {
                let preparedCore = try WorkspaceSQLiteDatastoreActor.strictlyPrepareCore(using: sqliteFixture.backend)
                let sqliteDatastore = WorkspaceSQLiteDatastoreActor(
                    preparedCoreRepository: sqliteFixture.coreRepository,
                    preparationReceipt: .init(core: preparedCore, local: .available(recovery: nil)),
                    preparedApplicationLocalRepository: sqliteFixture.localRepository,
                    traceRuntime: traceRuntime
                )
                let workspaceStore = WorkspaceStore()
                let watchedRoot = URL(fileURLWithPath: "/tmp/repository-cache-save-lifetime")
                let watchedPath = try #require(workspaceStore.mutationCoordinator.addWatchedPath(watchedRoot))
                let repository = workspaceStore.addRepo(at: watchedRoot.appending(path: "repository"))
                let worktree = try #require(repository.worktrees.single)
                let topologyPersistence = RepositoryTopologyStore(
                    atom: workspaceStore.repositoryTopologyAtom,
                    sqliteDatastore: sqliteDatastore
                )
                try await topologyPersistence.flushAsync()

                let repoCache = RepoCacheAtom()
                let cacheStore = RepoCacheStore(atom: repoCache, sqliteDatastore: sqliteDatastore)
                let coordinator = WorkspaceCacheCoordinator(
                    workspaceStore: workspaceStore,
                    repoCache: repoCache,
                    topologyPersistence: topologyPersistence,
                    validateSourceObservations: { _ in true },
                    scopeSyncHandler: { _ in }
                )
                lifecycleCoordinator = coordinator
                let oldEnrichment = cacheEnrichment(
                    repoID: repository.id,
                    worktreeID: worktree.id,
                    version: .old
                )
                repoCache.setRepoEnrichment(oldEnrichment.repository)
                repoCache.setWorktreeEnrichment(oldEnrichment.worktree)

                let heldSave = Task { @MainActor in
                    try await cacheStore.flushAsync(for: workspaceID)
                }
                obsoleteSave = heldSave
                await assertEventuallyAsync("obsolete cache save reaches the pre-SQL trace barrier") {
                    await firstSaveBarrier.isFirstSavePaused
                }
                try #require(await firstSaveBarrier.isFirstSavePaused)

                try await hideAndReturnRepository(
                    LifecycleContext(
                        workspaceStore: workspaceStore,
                        repoCache: repoCache,
                        coordinator: coordinator,
                        watchedRoot: watchedRoot,
                        watchedPath: watchedPath,
                        repository: repository,
                        worktree: worktree
                    )
                )
                let currentEnrichment = cacheEnrichment(
                    repoID: repository.id,
                    worktreeID: worktree.id,
                    version: .current
                )
                repoCache.setRepoEnrichment(currentEnrichment.repository)
                repoCache.setWorktreeEnrichment(currentEnrichment.worktree)
                try await cacheStore.flushAsync(for: workspaceID)

                await firstSaveBarrier.releaseFirstSave()
                let obsoleteSaveResult = await heldSave.result
                obsoleteSave = nil
                await coordinator.shutdown()
                lifecycleCoordinator = nil
                if case .failure(let error) = obsoleteSaveResult {
                    #expect(error is CancellationError)
                }

                let rawPersistedState = try sqliteFixture.localRepository.fetchCacheState()
                #expect(rawPersistedState.repoEnrichmentByRepoId[repository.id] == currentEnrichment.repository)
                #expect(rawPersistedState.worktreeEnrichmentByWorktreeId[worktree.id] == currentEnrichment.worktree)

                let restoredCache = RepoCacheAtom()
                await RepoCacheStore(atom: restoredCache, sqliteDatastore: sqliteDatastore)
                    .restoreAsync(for: workspaceID)
                #expect(restoredCache.repoEnrichmentByRepoId[repository.id] == currentEnrichment.repository)
                #expect(restoredCache.worktreeEnrichmentByWorktreeId[worktree.id] == currentEnrichment.worktree)
                try await traceRuntime.shutdown()
            } catch {
                await firstSaveBarrier.releaseFirstSave()
                if let obsoleteSave {
                    _ = await obsoleteSave.result
                }
                if let lifecycleCoordinator {
                    await lifecycleCoordinator.shutdown()
                }
                try? await traceRuntime.shutdown()
                throw error
            }
        }
    }

    @Test("a postcommit cancellation cannot suppress the corrective autosave")
    func postcommitCancellationCannotLeaveSupersededEnrichmentPersisted() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let scenario = try await makePostcommitScenario()
            var heldCurrentSave: Task<Void, Error>?
            do {
                let baselineEnrichment = RepoEnrichment.awaitingOrigin(repoId: scenario.repository.id)
                scenario.repoCache.setRepoEnrichment(baselineEnrichment)
                try await scenario.cacheStore.flushAsync(for: scenario.workspaceID)
                scenario.cacheStore.startObserving()
                await scenario.saveBarrier.armForNextSucceededSave()

                let currentEnrichment = cacheEnrichment(
                    repoID: scenario.repository.id,
                    worktreeID: scenario.worktree.id,
                    version: .current
                )
                scenario.repoCache.setRepoEnrichment(currentEnrichment.repository)
                scenario.repoCache.setWorktreeEnrichment(currentEnrichment.worktree)
                let heldSave = Task { @MainActor in
                    try await scenario.cacheStore.flushAsync(for: scenario.workspaceID)
                }
                heldCurrentSave = heldSave
                await assertEventuallyAsync("current cache save pauses after its SQL commit") {
                    await scenario.saveBarrier.isSavePausedAfterCommit
                }
                try #require(await scenario.saveBarrier.isSavePausedAfterCommit)
                let postcommitState = try scenario.sqliteFixture.localRepository.fetchCacheState()
                #expect(
                    postcommitState.repoEnrichmentByRepoId[scenario.repository.id] == currentEnrichment.repository)
                #expect(
                    postcommitState.worktreeEnrichmentByWorktreeId[scenario.worktree.id] == currentEnrichment.worktree)

                try await hideAndReturnRepository(scenario.lifecycleContext)
                #expect(scenario.repoCache.repoEnrichmentByRepoId[scenario.repository.id] == baselineEnrichment)
                #expect(scenario.repoCache.worktreeEnrichmentByWorktreeId[scenario.worktree.id] == nil)
                await assertEventuallyAsync("corrective autosave registers one debounce wait") {
                    scenario.clock.pendingSleepCount == 1
                }
                try #require(scenario.clock.pendingSleepCount == 1)
                scenario.clock.advance(by: .milliseconds(10))

                await scenario.saveBarrier.releasePausedSave()
                let heldSaveResult = await heldSave.result
                heldCurrentSave = nil
                if case .failure(let error) = heldSaveResult {
                    #expect(error is CancellationError)
                }
                await assertEventuallyAsync(
                    "the non-forced corrective autosave commits",
                    timeout: .milliseconds(250)
                ) {
                    await scenario.saveBarrier.didObserveCorrectiveSaveSucceeded
                }
                try #require(await scenario.saveBarrier.didObserveCorrectiveSaveSucceeded)

                let correctedState = try scenario.sqliteFixture.localRepository.fetchCacheState()
                #expect(correctedState.repoEnrichmentByRepoId[scenario.repository.id] == baselineEnrichment)
                #expect(correctedState.worktreeEnrichmentByWorktreeId[scenario.worktree.id] == nil)
                #expect(scenario.recoveryRecorder.events.isEmpty)

                try await scenario.cacheStore.flushAsync(for: scenario.workspaceID)
                let restoredCache = RepoCacheAtom()
                await RepoCacheStore(atom: restoredCache, sqliteDatastore: scenario.sqliteDatastore)
                    .restoreAsync(for: scenario.workspaceID)
                #expect(restoredCache.repoEnrichmentByRepoId[scenario.repository.id] == baselineEnrichment)
                #expect(restoredCache.worktreeEnrichmentByWorktreeId[scenario.worktree.id] == nil)
                await scenario.coordinator.shutdown()
                try await scenario.traceRuntime.shutdown()
            } catch {
                await scenario.saveBarrier.releasePausedSave()
                if let heldCurrentSave {
                    _ = await heldCurrentSave.result
                }
                try? await scenario.cacheStore.flushAsync(for: scenario.workspaceID)
                await scenario.coordinator.shutdown()
                try? await scenario.traceRuntime.shutdown()
                throw error
            }
        }
    }

    private func makePostcommitScenario() async throws -> PostcommitScenario {
        let workspaceID = UUIDv7.generate()
        let sqliteFixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let saveBarrier = PostcommitRepoCacheSaveTraceBarrier()
        let traceRuntime = makeTraceRuntime(postcommitBarrier: saveBarrier)
        do {
            let preparedCore = try WorkspaceSQLiteDatastoreActor.strictlyPrepareCore(using: sqliteFixture.backend)
            let sqliteDatastore = WorkspaceSQLiteDatastoreActor(
                preparedCoreRepository: sqliteFixture.coreRepository,
                preparationReceipt: .init(core: preparedCore, local: .available(recovery: nil)),
                preparedApplicationLocalRepository: sqliteFixture.localRepository,
                traceRuntime: traceRuntime
            )
            let workspaceStore = WorkspaceStore()
            let watchedRoot = URL(fileURLWithPath: "/tmp/repository-cache-postcommit-lifetime")
            let watchedPath = try #require(workspaceStore.mutationCoordinator.addWatchedPath(watchedRoot))
            let repository = workspaceStore.addRepo(at: watchedRoot.appending(path: "repository"))
            let worktree = try #require(repository.worktrees.single)
            let topologyPersistence = RepositoryTopologyStore(
                atom: workspaceStore.repositoryTopologyAtom,
                sqliteDatastore: sqliteDatastore
            )
            try await topologyPersistence.flushAsync()
            let repoCache = RepoCacheAtom()
            let clock = TestPushClock()
            let recoveryRecorder = PersistenceRecoveryRecorder()
            let cacheStore = RepoCacheStore(
                atom: repoCache,
                sqliteDatastore: sqliteDatastore,
                persistDebounceDuration: .milliseconds(10),
                clock: clock,
                recoveryReporter: recoveryRecorder.record
            )
            let coordinator = WorkspaceCacheCoordinator(
                workspaceStore: workspaceStore,
                repoCache: repoCache,
                topologyPersistence: topologyPersistence,
                validateSourceObservations: { _ in true },
                scopeSyncHandler: { _ in }
            )
            return PostcommitScenario(
                workspaceID: workspaceID,
                sqliteFixture: sqliteFixture,
                sqliteDatastore: sqliteDatastore,
                repoCache: repoCache,
                cacheStore: cacheStore,
                clock: clock,
                coordinator: coordinator,
                lifecycleContext: LifecycleContext(
                    workspaceStore: workspaceStore,
                    repoCache: repoCache,
                    coordinator: coordinator,
                    watchedRoot: watchedRoot,
                    watchedPath: watchedPath,
                    repository: repository,
                    worktree: worktree
                ),
                repository: repository,
                worktree: worktree,
                saveBarrier: saveBarrier,
                traceRuntime: traceRuntime,
                recoveryRecorder: recoveryRecorder
            )
        } catch {
            try? await traceRuntime.shutdown()
            throw error
        }
    }

    private func hideAndReturnRepository(_ context: LifecycleContext) async throws {
        let registration = FSEventRegistrationToken(
            sourceID: .init(kind: .watchedParentMembership, rootID: context.watchedPath.id),
            registrationGeneration: 1,
            rootGeneration: 1
        )
        let absenceTime = RepositoryRetentionTime(
            utc: Date(timeIntervalSince1970: 200),
            bootID: "repository-cache-save-lifetime",
            uptimeNanoseconds: 200_000_000_000
        )
        await context.coordinator.consumeWatchedFolderObservation(
            WatchedFolderTopologyObservation(
                root: context.watchedRoot,
                registration: registration,
                entries: [],
                otherObservedPaths: [],
                coverage: .authoritative(absenceTime),
                baselineMembershipRevision: context.workspaceStore.repositoryTopologyAtom.worktreePathIndexGeneration,
                incompleteOtherScopes: []
            ),
            sequence: 1
        )
        #expect(context.workspaceStore.repositoryTopologyAtom.isRepoUnavailable(context.repository.id))
        #expect(context.repoCache.repoEnrichmentByRepoId[context.repository.id] == nil)
        #expect(context.repoCache.worktreeEnrichmentByWorktreeId[context.worktree.id] == nil)

        await context.coordinator.consumeWatchedFolderObservation(
            WatchedFolderTopologyObservation(
                root: context.watchedRoot,
                registration: registration,
                entries: [
                    .init(
                        path: context.repository.repoPath,
                        kind: .cloneRoot,
                        repositoryKey: context.repository.repoPath.path
                    )
                ],
                otherObservedPaths: [],
                coverage: .additive,
                baselineMembershipRevision: context.workspaceStore.repositoryTopologyAtom.worktreePathIndexGeneration,
                incompleteOtherScopes: []
            ),
            sequence: 2
        )
        let returnedRepository = try #require(
            context.workspaceStore.repositoryTopologyAtom.repo(context.repository.id)
        )
        #expect(returnedRepository.worktrees.single?.id == context.worktree.id)
        #expect(!context.workspaceStore.repositoryTopologyAtom.isRepoUnavailable(context.repository.id))
    }

    private func makeTraceRuntime(
        firstSaveBarrier: FirstRepoCacheSaveTraceBarrier
    ) -> AgentStudioTraceRuntime {
        AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_NAME": "repository-cache-save-lifetime",
                "AGENTSTUDIO_TRACE_TAGS": "persistence.operation",
            ]),
            processIdentifier: 912,
            sinkFactory: AgentStudioTraceSinkFactory(
                makeJSONLSink: { _ in firstSaveBarrier },
                makeOTLPSink: { _ in firstSaveBarrier }
            ),
            timeUnixNano: { 1000 }
        )
    }

    private func makeTraceRuntime(
        postcommitBarrier: PostcommitRepoCacheSaveTraceBarrier
    ) -> AgentStudioTraceRuntime {
        AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_NAME": "repository-cache-postcommit-lifetime",
                "AGENTSTUDIO_TRACE_TAGS": "persistence.operation",
            ]),
            processIdentifier: 913,
            sinkFactory: AgentStudioTraceSinkFactory(
                makeJSONLSink: { _ in postcommitBarrier },
                makeOTLPSink: { _ in postcommitBarrier }
            ),
            timeUnixNano: { 1000 }
        )
    }

    private func cacheEnrichment(
        repoID: UUID,
        worktreeID: UUID,
        version: CacheVersion
    ) -> (repository: RepoEnrichment, worktree: WorktreeEnrichment) {
        (
            repository: .resolvedRemote(
                repoId: repoID,
                raw: RawRepoOrigin(origin: version.origin, upstream: nil),
                identity: RepoIdentity(
                    groupKey: version.groupKey,
                    remoteSlug: nil,
                    organizationName: "example",
                    displayName: version.rawValue
                ),
                updatedAt: version.updatedAt
            ),
            worktree: WorktreeEnrichment(
                worktreeId: worktreeID,
                repoId: repoID,
                branch: version.branch,
                isMainWorktree: true,
                updatedAt: version.updatedAt.addingTimeInterval(1)
            )
        )
    }

    private struct LifecycleContext {
        let workspaceStore: WorkspaceStore
        let repoCache: RepoCacheAtom
        let coordinator: WorkspaceCacheCoordinator
        let watchedRoot: URL
        let watchedPath: WatchedPath
        let repository: Repo
        let worktree: Worktree
    }

    private struct PostcommitScenario {
        let workspaceID: UUID
        let sqliteFixture: WorkspaceSQLiteBridgeFixture
        let sqliteDatastore: WorkspaceSQLiteDatastoreActor
        let repoCache: RepoCacheAtom
        let cacheStore: RepoCacheStore
        let clock: TestPushClock
        let coordinator: WorkspaceCacheCoordinator
        let lifecycleContext: LifecycleContext
        let repository: Repo
        let worktree: Worktree
        let saveBarrier: PostcommitRepoCacheSaveTraceBarrier
        let traceRuntime: AgentStudioTraceRuntime
        let recoveryRecorder: PersistenceRecoveryRecorder
    }

    private enum CacheVersion: String {
        case old
        case current

        var branch: String { "\(rawValue)-branch" }
        var groupKey: String { "remote:example/\(rawValue)" }
        var origin: String { "git@github.com:example/\(rawValue).git" }
        var updatedAt: Date { Date(timeIntervalSince1970: self == .old ? 100 : 300) }
    }

    @MainActor
    private final class PersistenceRecoveryRecorder {
        private(set) var events: [PersistenceRecoveryEvent] = []

        func record(_ event: PersistenceRecoveryEvent) {
            events.append(event)
        }
    }
}

private actor FirstRepoCacheSaveTraceBarrier: AgentStudioTraceSink {
    private var matchingSaveStartCount = 0
    private var firstSavePauseContinuation: CheckedContinuation<Void, Never>?
    private var shouldReleaseFirstSave = false
    private(set) var isFirstSavePaused = false

    func record(_ record: AgentStudioTraceRecord) async throws {
        guard isRepoCacheSaveStart(record) else { return }
        matchingSaveStartCount += 1
        guard matchingSaveStartCount == 1 else { return }

        isFirstSavePaused = true
        guard !shouldReleaseFirstSave else { return }
        await withCheckedContinuation { continuation in
            firstSavePauseContinuation = continuation
        }
    }

    func releaseFirstSave() {
        shouldReleaseFirstSave = true
        firstSavePauseContinuation?.resume()
        firstSavePauseContinuation = nil
    }

    func flush() async throws {}

    func shutdown() async throws {
        releaseFirstSave()
    }

    func diagnostics() async -> AgentStudioTraceWriterDiagnostics {
        .empty
    }

    private func isRepoCacheSaveStart(_ record: AgentStudioTraceRecord) -> Bool {
        record.body == "persistence.operation.phase"
            && record.attributes["agentstudio.persistence.operation"] == .string("repo_cache.save")
            && record.attributes["agentstudio.persistence.phase"] == .string("write_local")
            && record.attributes["agentstudio.persistence.lane"] == .string("repo_cache")
            && record.attributes["agentstudio.persistence.outcome"] == .string("started")
    }
}

private actor PostcommitRepoCacheSaveTraceBarrier: AgentStudioTraceSink {
    private var isArmed = false
    private var matchingSucceededSaveCount = 0
    private var pausedSaveContinuation: CheckedContinuation<Void, Never>?
    private var shouldReleasePausedSave = false
    private(set) var isSavePausedAfterCommit = false
    private(set) var didObserveCorrectiveSaveSucceeded = false

    func armForNextSucceededSave() {
        isArmed = true
    }

    func record(_ record: AgentStudioTraceRecord) async throws {
        guard isArmed, isRepoCacheSaveSucceeded(record) else { return }
        matchingSucceededSaveCount += 1
        if matchingSucceededSaveCount == 1 {
            isSavePausedAfterCommit = true
            guard !shouldReleasePausedSave else { return }
            await withCheckedContinuation { continuation in
                pausedSaveContinuation = continuation
            }
        } else {
            didObserveCorrectiveSaveSucceeded = true
        }
    }

    func releasePausedSave() {
        shouldReleasePausedSave = true
        pausedSaveContinuation?.resume()
        pausedSaveContinuation = nil
    }

    func flush() async throws {}

    func shutdown() async throws {
        releasePausedSave()
    }

    func diagnostics() async -> AgentStudioTraceWriterDiagnostics {
        .empty
    }

    private func isRepoCacheSaveSucceeded(_ record: AgentStudioTraceRecord) -> Bool {
        record.body == "persistence.operation.phase"
            && record.attributes["agentstudio.persistence.operation"] == .string("repo_cache.save")
            && record.attributes["agentstudio.persistence.phase"] == .string("write_local")
            && record.attributes["agentstudio.persistence.lane"] == .string("repo_cache")
            && record.attributes["agentstudio.persistence.outcome"] == .string("succeeded")
    }
}
