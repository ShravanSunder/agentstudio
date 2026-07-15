import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceSurfaceCoordinatorFilesystemSourceTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("filesystem source writes preserve serial operation order")
    func filesystemSourceWritesPreserveSerialOperationOrder() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir.appending(path: "source-order-repo"))
        let mainWorktree = try #require(harness.store.repo(repo.id)?.worktrees.first { $0.isMainWorktree })
        let featureWorktree = Worktree(
            repoId: repo.id,
            name: "feature",
            path: repo.repoPath.appending(path: "feature")
        )
        harness.store.reconcileDiscoveredWorktrees(repo.id, worktrees: [mainWorktree, featureWorktree])
        let reconciledFeature = try #require(
            harness.store.repo(repo.id)?.worktrees.first(where: { $0.path == featureWorktree.path })
        )

        let pane = harness.store.createPane(
            launchDirectory: mainWorktree.path,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: mainWorktree.id, cwd: mainWorktree.path)
        )
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        let source = OrderedRecordingFilesystemSource()
        let coordinator = makeCoordinator(
            store: harness.store,
            source: source,
            index: FilesystemProjectionIndex(),
            bus: harness.bus
        )
        defer { Task { await coordinator.shutdown() } }
        coordinator.syncFilesystemRootsAndActivity()

        await source.waitForOperation(.assertTopology)

        let operations = await source.operations()
        let registerOperations = operations.compactMap(\.registeredWorktreeId)
        #expect(registerOperations.first == mainWorktree.id)
        #expect(Set(registerOperations) == Set([mainWorktree.id, reconciledFeature.id]))
        let firstRegister = try #require(operations.firstIndex { $0.isRegister })
        let firstActivity = try #require(operations.firstIndex { $0.isActivity })
        let firstActivePane = try #require(operations.firstIndex { $0.isActivePane })
        let firstAssertTopology = try #require(operations.firstIndex { $0.isAssertTopology })
        #expect(firstRegister < firstActivity)
        #expect(firstActivity < firstActivePane)
        #expect(firstActivePane < firstAssertTopology)
    }

    @Test("stale source sync result is discarded before source side effects")
    func staleSourceSyncResultIsDiscardedBeforeSourceSideEffects() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir.appending(path: "stale-source-repo"))
        let mainWorktree = try #require(harness.store.repo(repo.id)?.worktrees.first { $0.isMainWorktree })
        let staleWorktree = Worktree(
            repoId: repo.id,
            name: "stale",
            path: repo.repoPath.appending(path: "stale")
        )
        harness.store.reconcileDiscoveredWorktrees(repo.id, worktrees: [mainWorktree, staleWorktree])
        let reconciledStale = try #require(
            harness.store.repo(repo.id)?.worktrees.first(where: { $0.path == staleWorktree.path })
        )

        let pane = harness.store.createPane(
            launchDirectory: mainWorktree.path,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: mainWorktree.id, cwd: mainWorktree.path)
        )
        harness.store.appendTab(Tab(paneId: pane.id))

        let source = OrderedRecordingFilesystemSource()
        let index = GateableFilesystemProjectionIndex()
        await index.pauseNextSourceSync()
        let coordinator = makeCoordinator(
            store: harness.store,
            source: source,
            index: index,
            bus: harness.bus
        )
        defer { Task { await coordinator.shutdown() } }

        await index.waitForPausedSourceSync()

        let latestWorktree = Worktree(
            repoId: repo.id,
            name: "latest",
            path: repo.repoPath.appending(path: "latest")
        )
        harness.store.reconcileDiscoveredWorktrees(repo.id, worktrees: [mainWorktree, latestWorktree])
        let reconciledLatest = try #require(
            harness.store.repo(repo.id)?.worktrees.first(where: { $0.path == latestWorktree.path })
        )
        coordinator.topologyDidChange(
            WorktreeTopologyDelta(
                repoId: repo.id,
                addedWorktreeIds: [reconciledLatest.id],
                removedWorktrees: [
                    RemovedWorktreeEntry(id: reconciledStale.id, path: reconciledStale.path)
                ],
                preservedWorktreeIds: [mainWorktree.id],
                didChange: true,
                traceId: nil
            )
        )

        await index.resumePausedSourceSync()
        coordinator.syncFilesystemRootsAndActivity()

        await source.waitForAssertTopology(worktreeIds: Set([mainWorktree.id, reconciledLatest.id]))

        let operations = await source.operations()
        #expect(!operations.contains(.register(worktreeId: reconciledStale.id)))
        #expect(operations.contains(.register(worktreeId: reconciledLatest.id)))
    }

    @Test("source sync commit failure requeues a fresh pass")
    func sourceSyncCommitFailureRequeuesFreshPass() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir.appending(path: "commit-requeue-repo"))
        let worktree = try #require(harness.store.repo(repo.id)?.worktrees.first { $0.isMainWorktree })
        let pane = harness.store.createPane(
            launchDirectory: worktree.path,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        harness.store.appendTab(Tab(paneId: pane.id))

        let source = OrderedRecordingFilesystemSource()
        let index = GateableFilesystemProjectionIndex()
        await index.failNextCommit()
        let coordinator = makeCoordinator(
            store: harness.store,
            source: source,
            index: index,
            bus: harness.bus
        )
        defer { Task { await coordinator.shutdown() } }

        await coordinator.waitForFilesystemRootsAndActivitySyncIdle()

        let operations = await source.operations()
        let topologyAssertions = operations.compactMap(\.assertedTopologyWorktreeIds)
        #expect(topologyAssertions.count >= 2)
        #expect(topologyAssertions.last == Set([worktree.id]))
    }

    @Test("stale projection result is dropped when pane context generation changes")
    func staleProjectionResultIsDroppedWhenPaneContextGenerationChanges() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir.appending(path: "stale-projection-repo"))
        let worktree = try #require(harness.store.repo(repo.id)?.worktrees.first { $0.isMainWorktree })
        let pane = harness.store.createPane(
            launchDirectory: worktree.path,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        harness.store.appendTab(Tab(paneId: pane.id))

        let source = OrderedRecordingFilesystemSource()
        let index = GateableFilesystemProjectionIndex()
        let paneFilesystemProjectionStore = PaneFilesystemProjectionAtom()
        let coordinator = makeCoordinator(
            store: harness.store,
            source: source,
            index: index,
            bus: harness.bus,
            paneFilesystemProjectionStore: paneFilesystemProjectionStore
        )
        defer { Task { await coordinator.shutdown() } }

        await source.waitForOperation(.assertTopology)

        await index.pauseNextProjection()
        let subscriber = await harness.makeSubscriber()
        await waitForBusSubscriberCount(harness.bus, atLeast: 1)

        let envelope = RuntimeEnvelopeHarness.filesystemEnvelope(
            event: .filesChanged(
                changeset: FileChangeset(
                    worktreeId: worktree.id,
                    repoId: repo.id,
                    rootPath: worktree.path,
                    paths: ["Sources/App.swift"],
                    timestamp: ContinuousClock().now,
                    batchSeq: 10
                )
            ),
            repoId: repo.id,
            worktreeId: worktree.id
        )

        let projectionTask = Task { @MainActor in
            await coordinator.handleFilesystemEnvelopeIfNeeded(envelope)
        }
        await index.waitForPausedProjection()

        coordinator.removePaneFilesystemProjectionContext(paneId: pane.id)
        await index.resumePausedProjection()
        _ = await projectionTask.value
        await Task.yield()

        let paneEvents = RuntimeEnvelopeHarness.paneEvents(from: await subscriber.snapshot())
        #expect(paneEvents.isEmpty)
        #expect(paneFilesystemProjectionStore.context(for: pane.id) == nil)

        await subscriber.shutdown()
    }

    @Test("newer filesystem envelope does not drop older valid projection")
    func newerFilesystemEnvelopeDoesNotDropOlderValidProjection() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let repo = harness.store.addRepo(at: harness.tempDir.appending(path: "projection-order-repo"))
        let worktree = try #require(harness.store.repo(repo.id)?.worktrees.first { $0.isMainWorktree })
        let pane = harness.store.createPane(
            launchDirectory: worktree.path,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        harness.store.appendTab(Tab(paneId: pane.id))

        let source = OrderedRecordingFilesystemSource()
        let index = GateableFilesystemProjectionIndex()
        let coordinator = makeCoordinator(
            store: harness.store,
            source: source,
            index: index,
            bus: harness.bus
        )
        defer { Task { await coordinator.shutdown() } }

        await source.waitForOperation(.assertTopology)
        await index.pauseNextProjection()
        let subscriber = await harness.makeSubscriber()
        await waitForBusSubscriberCount(harness.bus, atLeast: 1)

        let olderEnvelope = RuntimeEnvelopeHarness.filesystemEnvelope(
            event: .filesChanged(
                changeset: FileChangeset(
                    worktreeId: worktree.id,
                    repoId: repo.id,
                    rootPath: worktree.path,
                    paths: ["Sources/App.swift"],
                    timestamp: ContinuousClock().now,
                    batchSeq: 10
                )
            ),
            repoId: repo.id,
            worktreeId: worktree.id
        )
        let newerEnvelope = RuntimeEnvelopeHarness.filesystemEnvelope(
            event: .filesChanged(
                changeset: FileChangeset(
                    worktreeId: worktree.id,
                    repoId: repo.id,
                    rootPath: worktree.path,
                    paths: ["Sources/Model.swift"],
                    timestamp: ContinuousClock().now,
                    batchSeq: 11
                )
            ),
            repoId: repo.id,
            worktreeId: worktree.id
        )

        let olderTask = Task { @MainActor in
            await coordinator.handleFilesystemEnvelopeIfNeeded(olderEnvelope)
        }
        await index.waitForPausedProjection()
        let newerTask = Task { @MainActor in
            await coordinator.handleFilesystemEnvelopeIfNeeded(newerEnvelope)
        }
        _ = await newerTask.value
        await index.resumePausedProjection()
        _ = await olderTask.value

        await assertEventuallyAsync("both valid projections should publish", maxTurns: 200_000) {
            let paneEvents = RuntimeEnvelopeHarness.paneEvents(from: await subscriber.snapshot())
            return paneEvents.count == 2
        }

        await subscriber.shutdown()
    }

    private func makeHarness() -> FilesystemCoordinatorHarness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-filesystem-coordinator-\(UUID().uuidString)")
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        return FilesystemCoordinatorHarness(
            store: store,
            bus: makeTestPaneRuntimeEventBus(),
            tempDir: tempDir
        )
    }

    private func makeCoordinator(
        store: WorkspaceStore,
        source: some WorkspaceFilesystemSourceManaging,
        index: some WorkspaceFilesystemProjectionIndexing,
        bus: EventBus<RuntimeEnvelope>,
        paneFilesystemProjectionStore: PaneFilesystemProjectionAtom = PaneFilesystemProjectionAtom()
    ) -> WorkspaceSurfaceCoordinator {
        WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: MockFilesystemCoordinatorSurfaceManager(),
            runtimeRegistry: RuntimeRegistry(),
            paneEventBus: bus,
            filesystemSource: source,
            filesystemProjectionIndex: index,
            paneFilesystemProjectionStore: paneFilesystemProjectionStore,
            windowLifecycleStore: WindowLifecycleAtom()
        )
    }
}

@MainActor
private struct FilesystemCoordinatorHarness {
    let store: WorkspaceStore
    let bus: EventBus<RuntimeEnvelope>
    let tempDir: URL

    func makeSubscriber() async -> RecordingSubscriber<RuntimeEnvelope> {
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        return RecordingSubscriber(stream: stream)
    }

    func shutdown() async {
        try? FileManager.default.removeItem(at: tempDir)
    }
}

private enum FilesystemSourceOperation: Sendable, Equatable {
    case register(worktreeId: UUID)
    case unregister(worktreeId: UUID)
    case activity(worktreeId: UUID, isActiveInApp: Bool)
    case activePane(worktreeId: UUID?)
    case assertTopology(worktreeIds: Set<UUID>)

    var registeredWorktreeId: UUID? {
        guard case .register(let worktreeId) = self else { return nil }
        return worktreeId
    }

    var kind: FilesystemSourceOperationKind {
        switch self {
        case .register:
            .register
        case .unregister:
            .unregister
        case .activity:
            .activity
        case .activePane:
            .activePane
        case .assertTopology:
            .assertTopology
        }
    }

    var isRegister: Bool {
        if case .register = self { return true }
        return false
    }

    var isActivity: Bool {
        if case .activity = self { return true }
        return false
    }

    var isActivePane: Bool {
        if case .activePane = self { return true }
        return false
    }

    var isAssertTopology: Bool {
        if case .assertTopology = self { return true }
        return false
    }

    var assertedTopologyWorktreeIds: Set<UUID>? {
        guard case .assertTopology(let worktreeIds) = self else { return nil }
        return worktreeIds
    }
}

private enum FilesystemSourceOperationKind: Sendable, Equatable {
    case register
    case unregister
    case activity
    case activePane
    case assertTopology
}

private struct OrderedFilesystemSourceSnapshot: Sendable {
    let registeredRoots: [UUID: URL]
}

private actor OrderedRecordingFilesystemSource: WorkspaceFilesystemSourceManaging {
    private var registeredRoots: [UUID: URL] = [:]
    private var activityByWorktreeId: [UUID: Bool] = [:]
    private var activePaneWorktreeId: UUID?
    private var operationLog: [FilesystemSourceOperation] = []
    private var operationWaiters: [FilesystemSourceOperationKind: [CheckedContinuation<Void, Never>]] = [:]
    private var topologyWaiters: [(Set<UUID>, CheckedContinuation<Void, Never>)] = []

    func start() async {}

    func shutdown() async {}

    func register(worktreeId: UUID, repoId _: UUID, rootPath: URL) async {
        registeredRoots[worktreeId] = rootPath
        appendOperation(.register(worktreeId: worktreeId))
    }

    func unregister(worktreeId: UUID) async {
        registeredRoots.removeValue(forKey: worktreeId)
        activityByWorktreeId.removeValue(forKey: worktreeId)
        if activePaneWorktreeId == worktreeId {
            activePaneWorktreeId = nil
        }
        appendOperation(.unregister(worktreeId: worktreeId))
    }

    func assertTopology(_ assertion: FilesystemTopologyAssertion) async {
        let desiredWorktreeIds = Set(assertion.contextsByWorktreeId.keys)
        registeredRoots = assertion.contextsByWorktreeId.mapValues(\.rootPath)
        activityByWorktreeId = activityByWorktreeId.filter { desiredWorktreeIds.contains($0.key) }
        if let activePaneWorktreeId, !desiredWorktreeIds.contains(activePaneWorktreeId) {
            self.activePaneWorktreeId = nil
        }
        appendOperation(.assertTopology(worktreeIds: desiredWorktreeIds))
    }

    func setActivity(worktreeId: UUID, isActiveInApp: Bool) async {
        activityByWorktreeId[worktreeId] = isActiveInApp
        appendOperation(.activity(worktreeId: worktreeId, isActiveInApp: isActiveInApp))
    }

    func setActivePaneWorktree(worktreeId: UUID?) async {
        activePaneWorktreeId = worktreeId
        appendOperation(.activePane(worktreeId: worktreeId))
    }

    func snapshot() -> OrderedFilesystemSourceSnapshot {
        OrderedFilesystemSourceSnapshot(registeredRoots: registeredRoots)
    }

    func operations() -> [FilesystemSourceOperation] {
        operationLog
    }

    func operationKinds() -> [FilesystemSourceOperationKind] {
        operationLog.map { operation in
            switch operation {
            case .register:
                .register
            case .unregister:
                .unregister
            case .activity:
                .activity
            case .activePane:
                .activePane
            case .assertTopology:
                .assertTopology
            }
        }
    }

    func waitForOperation(_ kind: FilesystemSourceOperationKind) async {
        guard !operationKinds().contains(kind) else { return }
        await withCheckedContinuation { continuation in
            operationWaiters[kind, default: []].append(continuation)
        }
    }

    func waitForAssertTopology(worktreeIds: Set<UUID>) async {
        if operationLog.contains(.assertTopology(worktreeIds: worktreeIds)) { return }
        await withCheckedContinuation { continuation in
            topologyWaiters.append((worktreeIds, continuation))
        }
    }

    private func appendOperation(_ operation: FilesystemSourceOperation) {
        operationLog.append(operation)
        let kind = operation.kind
        let waiters = operationWaiters.removeValue(forKey: kind) ?? []
        for waiter in waiters {
            waiter.resume()
        }
        guard case .assertTopology(let worktreeIds) = operation else { return }
        var remainingWaiters: [(Set<UUID>, CheckedContinuation<Void, Never>)] = []
        for (expectedWorktreeIds, continuation) in topologyWaiters {
            if expectedWorktreeIds == worktreeIds {
                continuation.resume()
            } else {
                remainingWaiters.append((expectedWorktreeIds, continuation))
            }
        }
        topologyWaiters = remainingWaiters
    }
}

private actor GateableFilesystemProjectionIndex: WorkspaceFilesystemProjectionIndexing {
    private let base = FilesystemProjectionIndex()
    private var commitFailuresRemaining = 0
    private var sourceSyncPauseCount = 0
    private var projectionPauseCount = 0
    private var pausedSourceSyncCount = 0
    private var pausedProjectionCount = 0
    private var pausedSourceSyncContinuations: [CheckedContinuation<Void, Never>] = []
    private var resumeSourceSyncContinuations: [CheckedContinuation<Void, Never>] = []
    private var pausedProjectionContinuations: [CheckedContinuation<Void, Never>] = []
    private var resumeProjectionContinuations: [CheckedContinuation<Void, Never>] = []

    func pauseNextSourceSync() {
        sourceSyncPauseCount += 1
    }

    func pauseNextProjection() {
        projectionPauseCount += 1
    }

    func failNextCommit() {
        commitFailuresRemaining += 1
    }

    func waitForPausedSourceSync() async {
        guard pausedSourceSyncCount == 0 else { return }
        await withCheckedContinuation { continuation in
            pausedSourceSyncContinuations.append(continuation)
        }
    }

    func waitForPausedProjection() async {
        guard pausedProjectionCount == 0 else { return }
        await withCheckedContinuation { continuation in
            pausedProjectionContinuations.append(continuation)
        }
    }

    func resumePausedSourceSync() {
        let continuations = resumeSourceSyncContinuations
        resumeSourceSyncContinuations.removeAll()
        pausedSourceSyncCount = 0
        for continuation in continuations {
            continuation.resume()
        }
    }

    func resumePausedProjection() {
        let continuations = resumeProjectionContinuations
        resumeProjectionContinuations.removeAll()
        pausedProjectionCount = 0
        for continuation in continuations {
            continuation.resume()
        }
    }

    func reconcileSourceSync(_ request: FilesystemSourceSyncRequest) async -> FilesystemSourceSyncDiff {
        if sourceSyncPauseCount > 0 {
            sourceSyncPauseCount -= 1
            pausedSourceSyncCount += 1
            for continuation in pausedSourceSyncContinuations {
                continuation.resume()
            }
            pausedSourceSyncContinuations.removeAll()
            await withCheckedContinuation { continuation in
                resumeSourceSyncContinuations.append(continuation)
            }
        }
        return await base.reconcileSourceSync(request)
    }

    func commitSourceSync(requestGeneration: UInt64, topologyGeneration: UInt64) async -> Bool {
        if commitFailuresRemaining > 0 {
            commitFailuresRemaining -= 1
            return false
        }
        return await base.commitSourceSync(requestGeneration: requestGeneration, topologyGeneration: topologyGeneration)
    }

    func applyPaneUpdate(_ update: FilesystemProjectionPaneUpdate) async {
        await base.applyPaneUpdate(update)
    }

    func projectPaneFilesystem(_ request: PaneFilesystemProjectionRequest) async -> PaneFilesystemProjectionResult {
        if projectionPauseCount > 0 {
            projectionPauseCount -= 1
            pausedProjectionCount += 1
            for continuation in pausedProjectionContinuations {
                continuation.resume()
            }
            pausedProjectionContinuations.removeAll()
            await withCheckedContinuation { continuation in
                resumeProjectionContinuations.append(continuation)
            }
        }
        return await base.projectPaneFilesystem(request)
    }
}

@MainActor
private final class MockFilesystemCoordinatorSurfaceManager: WorkspaceSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>

    init() {
        cwdStream = AsyncStream { continuation in
            continuation.onTermination = { _ in }
        }
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> {
        cwdStream
    }

    func syncFocus(activeSurfaceId _: UUID?) {}

    func createSurface(
        config _: Ghostty.SurfaceConfiguration,
        metadata _: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        .failure(.ghosttyNotInitialized)
    }

    @discardableResult
    func attach(_: UUID, to _: UUID) -> Ghostty.SurfaceView? { nil }

    func detach(_: UUID, reason _: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? { nil }

    func requeueUndo(_: UUID) {}

    func destroy(_: UUID) {}
}
