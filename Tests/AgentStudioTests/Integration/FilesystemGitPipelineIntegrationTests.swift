import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct FilesystemGitPipelineIntegrationTests {
    @Test("pipeline emits filesystem and git snapshot facts that converge projection stores")
    func pipelineEmitsFilesystemAndGitSnapshotFacts() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let pipeline = FilesystemGitPipeline(
            bus: bus,
            gitWorkingTreeProvider: .stub { _ in
                GitWorkingTreeStatus(
                    summary: GitWorkingTreeSummary(changed: 2, staged: 1, untracked: 1),
                    branch: "feature/pipeline",
                    origin: nil
                )
            },
            filesystemDebounceWindow: .zero,
            filesystemMaxFlushLatency: .zero
        )
        await pipeline.start()

        let rootPath = FileManager.default.temporaryDirectory
            .appending(path: "pipeline-int-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootPath) }

        let worktreeId = UUID()
        let repoId = UUID()
        let workspaceDir = FileManager.default.temporaryDirectory
            .appending(path: "pipeline-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspaceDir) }
        let store = WorkspaceStore()
        let repoCache = RepoCacheAtom()
        let cacheCoordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: store,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        let observed = ObservedFilesystemGitEvents()

        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let consumerTask = Task { @MainActor in
            for await envelope in stream {
                cacheCoordinator.consume(envelope)
                await observed.record(envelope)
            }
        }
        await waitForSubscriberCount(bus: bus, atLeast: 3)
        await pipeline.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
        await pipeline.enqueueRawPathsForTesting(
            worktreeId: worktreeId,
            paths: ["Sources/Feature.swift"]
        )

        let receivedFilesChanged = await eventually("filesChanged fact should be posted") {
            await observed.filesChangedCount(for: worktreeId) >= 1
        }
        #expect(receivedFilesChanged)
        let filesChangedPayloadConverged = await eventually("filesChanged payload should retain projected path") {
            await observed.hasSeenFilesChangedPath("Sources/Feature.swift", for: worktreeId)
        }
        #expect(filesChangedPayloadConverged)

        let receivedGitSnapshot = await eventually("gitSnapshotChanged fact should be posted") {
            await observed.gitSnapshotCount(for: worktreeId) >= 1
        }
        #expect(receivedGitSnapshot)

        let gitStoreConverged = await eventually("workspace cache enrichment should update") {
            guard let snapshot = repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.snapshot else { return false }
            return snapshot.summary.changed == 2
                && snapshot.summary.staged == 1
                && snapshot.summary.untracked == 1
                && snapshot.branch == "feature/pipeline"
        }
        #expect(gitStoreConverged)

        await shutdownWorld(
            pipeline: pipeline,
            observerTasks: [consumerTask],
            bus: bus
        )
    }

    @Test("periodic git refresh updates cache sync state without filesystem ingress")
    func periodicGitRefreshUpdatesCacheWithoutFilesystemIngress() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let gitClock = TestPushClock()
        let tierCadence = Duration.milliseconds(120)
        let refreshPolicy = AppPolicies.GitRefresh.Policy(
            activePaneCadence: tierCadence,
            visibleSidebarCadence: tierCadence,
            openPaneCadence: tierCadence,
            backgroundCadence: tierCadence,
            backgroundStripeCount: 1
        )
        let provider = MutableGitWorkingTreeStatusProvider(
            status: makeTrackedStatus()
        )
        let pipeline = FilesystemGitPipeline(
            bus: bus,
            gitWorkingTreeProvider: provider,
            fseventStreamClient: SilentFSEventStreamClient(),
            filesystemDebounceWindow: .zero,
            filesystemMaxFlushLatency: .zero,
            gitCoalescingWindow: .zero,
            gitPeriodicRefreshInterval: refreshPolicy.activePaneCadence,
            gitRefreshPolicy: refreshPolicy,
            gitSleepClock: gitClock
        )
        await pipeline.start()

        let rootPath = FileManager.default.temporaryDirectory
            .appending(path: "pipeline-periodic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootPath) }

        let worktreeId = UUID()
        let repoId = UUID()
        let workspaceDir = FileManager.default.temporaryDirectory
            .appending(path: "pipeline-periodic-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspaceDir) }
        let store = WorkspaceStore()
        let repoCache = RepoCacheAtom()
        let cacheReceipt = PeriodicGitCacheReceipt()
        let cacheCoordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: store,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        let coordinatorStream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let coordinatorTask = Task { @MainActor in
            for await envelope in coordinatorStream {
                cacheCoordinator.consume(envelope)
                if let snapshot = repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.snapshot {
                    await cacheReceipt.record(snapshot)
                }
            }
        }
        await waitForSubscriberCount(bus: bus, atLeast: 3)
        await pipeline.setSidebarVisibleWorktrees([worktreeId])
        await pipeline.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)

        let initialSnapshotArrived = await eventually("initial periodic snapshot should arrive") {
            guard let snapshot = repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.snapshot else { return false }
            return snapshot.summary.aheadCount == 0 && snapshot.summary.behindCount == 0
        }
        #expect(initialSnapshotArrived)
        let firstRefreshSleepScheduled = await waitUntilYielding {
            gitClock.pendingSleepCount > 0
        }
        #expect(firstRefreshSleepScheduled)

        let refreshContext = PeriodicGitRefreshContext(
            clock: gitClock,
            provider: provider,
            cacheReceipt: cacheReceipt,
            cadence: refreshPolicy.activePaneCadence,
            repoCache: repoCache,
            worktreeId: worktreeId
        )
        await runPeriodicGitRefreshPhase(
            .init(status: makeTrackedStatus(aheadCount: 1), expectedStatusReadCount: 2),
            context: refreshContext
        )
        await runPeriodicGitRefreshPhase(
            .init(status: makeTrackedStatus(behindCount: 2), expectedStatusReadCount: 3),
            context: refreshContext
        )

        await shutdownWorld(
            pipeline: pipeline,
            observerTasks: [coordinatorTask],
            bus: bus
        )
    }

    @Test("active pane worktree switch triggers git refresh without periodic cadence")
    func activePaneWorktreeSwitchTriggersGitRefreshWithoutPeriodicCadence() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let provider = MutableGitWorkingTreeStatusProvider(
            status: makeTrackedStatus(branch: "main")
        )
        let pipeline = FilesystemGitPipeline(
            bus: bus,
            gitWorkingTreeProvider: provider,
            fseventStreamClient: SilentFSEventStreamClient(),
            filesystemDebounceWindow: .zero,
            filesystemMaxFlushLatency: .zero,
            gitCoalescingWindow: .zero,
            gitPeriodicRefreshInterval: nil
        )
        await pipeline.start()

        let rootPath = FileManager.default.temporaryDirectory
            .appending(path: "pipeline-focus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootPath) }

        let worktreeId = UUID()
        let repoId = UUID()
        let workspaceDir = FileManager.default.temporaryDirectory
            .appending(path: "pipeline-focus-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspaceDir) }
        let store = WorkspaceStore()
        let repoCache = RepoCacheAtom()
        let cacheCoordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: store,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        let coordinatorStream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let coordinatorTask = Task { @MainActor in
            for await envelope in coordinatorStream {
                cacheCoordinator.consume(envelope)
            }
        }
        await waitForSubscriberCount(bus: bus, atLeast: 3)
        await pipeline.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)

        let initialSnapshotArrived = await eventually("initial focus test snapshot should arrive") {
            repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "main"
        }
        #expect(initialSnapshotArrived)

        await provider.setStatus(makeTrackedStatus(branch: "focused"))
        await pipeline.setActivePaneWorktree(worktreeId: worktreeId)

        let focusRefreshArrived = await eventually("focus switch should refresh without periodic cadence") {
            repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "focused"
        }
        #expect(focusRefreshArrived)

        await shutdownWorld(
            pipeline: pipeline,
            observerTasks: [coordinatorTask],
            bus: bus
        )
    }

    @Test("explicit watched-folder refresh bypasses filesystem-derived git coalescing")
    func explicitWatchedFolderRefreshBypassesGitCoalescing() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let gitClock = TestPushClock()
        let provider = MutableGitWorkingTreeStatusProvider(status: makeTrackedStatus(branch: "initial"))
        let pipeline = FilesystemGitPipeline(
            bus: bus,
            gitWorkingTreeProvider: provider,
            fseventStreamClient: SilentFSEventStreamClient(),
            filesystemDebounceWindow: .zero,
            filesystemMaxFlushLatency: .zero,
            gitCoalescingWindow: .milliseconds(500),
            gitPeriodicRefreshInterval: nil,
            gitSleepClock: gitClock
        )
        await pipeline.start()

        let rootPath = FileManager.default.temporaryDirectory
            .appending(path: "pipeline-explicit-refresh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootPath) }

        let worktreeId = UUID()
        await pipeline.register(worktreeId: worktreeId, repoId: UUID(), rootPath: rootPath)
        let initialReadCompleted = await eventually("registration should perform its immediate read") {
            await provider.callCount == 1
        }
        #expect(initialReadCompleted)

        await provider.setStatus(makeTrackedStatus(branch: "manual"))
        _ = await pipeline.refreshWatchedFolders([])
        let explicitReadCompletedWithoutClockAdvance = await eventually(
            "explicit refresh should bypass the filesystem-derived coalescing window"
        ) {
            await provider.callCount == 2
        }
        #expect(explicitReadCompletedWithoutClockAdvance)

        await pipeline.shutdown()
    }

    @Test("watched-folder refresh requests git status only for intersecting registered worktrees")
    func watchedFolderRefreshRequestsGitStatusOnlyForIntersectingRegisteredWorktrees() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let provider = MutableGitWorkingTreeStatusProvider(status: makeTrackedStatus())
        let pipeline = FilesystemGitPipeline(
            bus: bus,
            gitWorkingTreeProvider: provider,
            fseventStreamClient: SilentFSEventStreamClient(),
            filesystemDebounceWindow: .zero,
            filesystemMaxFlushLatency: .zero,
            gitCoalescingWindow: .zero,
            gitPeriodicRefreshInterval: nil
        )
        await pipeline.start()

        let fixtureRoot = FileManager.default.temporaryDirectory
            .appending(path: "pipeline-watched-scope-\(UUIDv7.generate().uuidString)")
        let watchedFolder = fixtureRoot.appending(path: "watched")
        let worktreeRoots = [
            watchedFolder.appending(path: "worktree-a"),
            fixtureRoot.appending(path: "unrelated/worktree-b"),
            fixtureRoot.appending(path: "unrelated/worktree-c"),
        ]
        for worktreeRoot in worktreeRoots {
            try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        for worktreeRoot in worktreeRoots {
            await pipeline.register(
                worktreeId: UUIDv7.generate(),
                repoId: UUIDv7.generate(),
                rootPath: worktreeRoot
            )
        }
        let registrationReadsCompleted = await eventually("all registration reads should complete") {
            await provider.callCount == worktreeRoots.count
        }
        #expect(registrationReadsCompleted)
        await provider.resetRecordedRequests()

        let watchedPaths = [WatchedPath(path: watchedFolder)]
        let summary = await pipeline.refreshWatchedFolders(watchedPaths)
        let affectedReadCompleted = await eventually("affected worktree git read should complete") {
            await provider.callCount >= 1
        }
        #expect(affectedReadCompleted)

        #expect(await provider.callCount(for: worktreeRoots[0]) == 1)
        #expect(await provider.callCount(for: worktreeRoots[1]) == 0)
        #expect(await provider.callCount(for: worktreeRoots[2]) == 0)
        #expect(Set(summary.repoPathsByWatchedFolder.keys) == [watchedFolder.standardizedFileURL])

        await provider.resetRecordedRequests()
        _ = await pipeline.refreshWatchedFolders([])
        let refreshAllReadsCompleted = await eventually("explicit refresh-all should read every worktree") {
            await provider.callCount == worktreeRoots.count
        }
        #expect(refreshAllReadsCompleted)
        for worktreeRoot in worktreeRoots {
            #expect(await provider.callCount(for: worktreeRoot) == 1)
        }

        await pipeline.shutdown()
    }

    private func makeTrackedStatus(
        aheadCount: Int = 0,
        behindCount: Int = 0,
        branch: String = "main",
        origin: String = "git@github.com:askluna/agent-studio.git"
    ) -> GitWorkingTreeStatus {
        GitWorkingTreeStatus(
            summary: GitWorkingTreeSummary(
                changed: 0,
                staged: 0,
                untracked: 0,
                linesAdded: 0,
                linesDeleted: 0,
                aheadCount: aheadCount,
                behindCount: behindCount,
                hasUpstream: true
            ),
            branch: branch,
            origin: origin
        )
    }

    @Test("pipeline retries origin discovery after initial empty origin and converges to remote identity")
    func pipelineRetriesOriginDiscoveryAfterInitialEmptyOrigin() async throws {
        func status(originResolution: GitOriginResolution) -> GitWorkingTreeStatus {
            GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                branch: "main",
                originResolution: originResolution
            )
        }

        let bus = EventBus<RuntimeEnvelope>()
        let provider = MutableGitWorkingTreeStatusProvider(status: status(originResolution: .awaitingResolution))
        let pipeline = FilesystemGitPipeline(
            bus: bus,
            gitWorkingTreeProvider: provider,
            fseventStreamClient: SilentFSEventStreamClient(),
            filesystemDebounceWindow: .zero,
            filesystemMaxFlushLatency: .zero,
            gitCoalescingWindow: .zero,
            gitPeriodicRefreshInterval: nil
        )
        await pipeline.start()

        let rootPath = FileManager.default.temporaryDirectory
            .appending(path: "pipeline-origin-retry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootPath) }

        let workspaceDir = FileManager.default.temporaryDirectory
            .appending(path: "pipeline-origin-retry-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspaceDir) }
        let workspaceStore = WorkspaceStore()
        let repo = workspaceStore.addRepo(at: rootPath)
        guard let worktreeId = repo.worktrees.first?.id else {
            Issue.record("Expected repo to have main worktree")
            await pipeline.shutdown()
            return
        }

        let repoCache = RepoCacheAtom()
        let cacheReceipt = OriginRetryCacheReceipt()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        let coordinatorStream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let coordinatorTask = Task { @MainActor in
            for await envelope in coordinatorStream {
                coordinator.consume(envelope)
                await cacheReceipt.record(
                    branch: repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.branch,
                    repoEnrichment: repoCache.repoEnrichmentByRepoId[repo.id]
                )
            }
        }
        await waitForSubscriberCount(bus: bus, atLeast: 3)
        await pipeline.register(worktreeId: worktreeId, repoId: repo.id, rootPath: rootPath)
        await pipeline.setSidebarVisibleWorktrees([worktreeId])

        await cacheReceipt.waitForInitialSnapshot()
        #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "main")

        await provider.setStatus(status(originResolution: .resolved("git@github.com:askluna/agent-studio.git")))
        await pipeline.enqueueRawPathsForTesting(worktreeId: worktreeId, paths: [".git/config"])

        await cacheReceipt.waitForRemoteIdentity()
        guard case .some(.resolvedRemote(_, let raw, let identity, _)) = repoCache.repoEnrichmentByRepoId[repo.id]
        else {
            Issue.record("git config change should resolve the remote identity")
            await shutdownWorld(pipeline: pipeline, observerTasks: [coordinatorTask], bus: bus)
            return
        }
        #expect(raw.origin == "git@github.com:askluna/agent-studio.git")
        #expect(identity.groupKey == "remote:askluna/agent-studio")

        await shutdownWorld(
            pipeline: pipeline,
            observerTasks: [coordinatorTask],
            bus: bus
        )
    }

    private func eventually(
        _ description: String,
        maxTurns: Int = 50_000,
        condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        for _ in 0..<maxTurns {
            if await condition() {
                return true
            }
            await Task.yield()
        }
        Issue.record("\(description) timed out")
        return false
    }

    private func waitUntilYielding(
        maxTurns: Int = 2000,
        condition: @escaping @Sendable () -> Bool
    ) async -> Bool {
        for _ in 0..<maxTurns {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return condition()
    }

    private struct AdvancePeriodicGitRefreshProps {
        let clock: TestPushClock
        let provider: MutableGitWorkingTreeStatusProvider
        let cacheReceipt: PeriodicGitCacheReceipt
        let cadence: Duration
        let expectedStatusReadCount: Int
        let expectedAheadCount: Int?
        let expectedBehindCount: Int?
    }

    private struct PeriodicGitRefreshContext {
        let clock: TestPushClock
        let provider: MutableGitWorkingTreeStatusProvider
        let cacheReceipt: PeriodicGitCacheReceipt
        let cadence: Duration
        let repoCache: RepoCacheAtom
        let worktreeId: UUID
    }

    private struct PeriodicGitRefreshPhase {
        let status: GitWorkingTreeStatus
        let expectedStatusReadCount: Int
    }

    private func runPeriodicGitRefreshPhase(
        _ phase: PeriodicGitRefreshPhase,
        context: PeriodicGitRefreshContext
    ) async {
        let expectedAheadCount = phase.status.summary.aheadCount
        let expectedBehindCount = phase.status.summary.behindCount
        await context.provider.setStatus(phase.status)
        await advancePeriodicGitRefresh(
            .init(
                clock: context.clock,
                provider: context.provider,
                cacheReceipt: context.cacheReceipt,
                cadence: context.cadence,
                expectedStatusReadCount: phase.expectedStatusReadCount,
                expectedAheadCount: expectedAheadCount,
                expectedBehindCount: expectedBehindCount
            )
        )
        let cacheConverged = await eventually("periodic refresh should update ahead/behind counts") {
            let summary = context.repoCache.worktreeEnrichmentByWorktreeId[context.worktreeId]?.snapshot?.summary
            return summary?.aheadCount == expectedAheadCount
                && summary?.behindCount == expectedBehindCount
        }
        #expect(cacheConverged)
        let nextRefreshSleepScheduled = await waitUntilYielding {
            context.clock.pendingSleepCount > 0
        }
        #expect(nextRefreshSleepScheduled)
    }

    private func advancePeriodicGitRefresh(_ props: AdvancePeriodicGitRefreshProps) async {
        let clock = props.clock
        let provider = props.provider
        let cacheReceipt = props.cacheReceipt
        let cadence = props.cadence
        let expectedStatusReadCount = props.expectedStatusReadCount
        let expectedAheadCount = props.expectedAheadCount
        let expectedBehindCount = props.expectedBehindCount
        await clock.waitForPendingSleepCount(atLeast: 1)
        guard let currentSleepGeneration = clock.pendingSleepGenerations.max() else {
            Issue.record("periodic refresh should have a pending sleep before clock advancement")
            return
        }
        let nextSleepGeneration = currentSleepGeneration + 1
        clock.advance(by: cadence)
        await provider.waitForCallCount(expectedStatusReadCount)
        await cacheReceipt.waitForSnapshot(
            aheadCount: expectedAheadCount,
            behindCount: expectedBehindCount
        )
        await clock.waitForPendingSleepGeneration(nextSleepGeneration)
    }

    private func waitForSubscriberCount(
        bus: EventBus<RuntimeEnvelope>,
        atLeast expectedCount: Int,
        maxTurns: Int = 2000
    ) async {
        let subscribed = await eventually("bus subscriber count should reach \(expectedCount)", maxTurns: maxTurns) {
            await bus.subscriberCount >= expectedCount
        }
        #expect(subscribed)
    }

    private func shutdownWorld(
        pipeline: FilesystemGitPipeline,
        observerTasks: [Task<Void, Never>],
        bus: EventBus<RuntimeEnvelope>
    ) async {
        await pipeline.shutdown()
        for observerTask in observerTasks {
            observerTask.cancel()
            await observerTask.value
        }
        let busDrained = await eventually("integration test world should leave no subscribers behind") {
            await bus.subscriberCount == 0
        }
        #expect(busDrained)
    }

}

private actor PeriodicGitCacheReceipt {
    private struct ExpectedCounts: Hashable {
        let aheadCount: Int?
        let behindCount: Int?
    }

    private var observedCounts: Set<ExpectedCounts> = []
    private var waiters: [ExpectedCounts: [CheckedContinuation<Void, Never>]] = [:]

    func record(_ snapshot: GitWorkingTreeSnapshot) {
        let counts = ExpectedCounts(
            aheadCount: snapshot.summary.aheadCount,
            behindCount: snapshot.summary.behindCount
        )
        observedCounts.insert(counts)
        let continuations = waiters.removeValue(forKey: counts) ?? []
        for continuation in continuations {
            continuation.resume()
        }
    }

    func waitForSnapshot(aheadCount: Int?, behindCount: Int?) async {
        let counts = ExpectedCounts(aheadCount: aheadCount, behindCount: behindCount)
        guard !observedCounts.contains(counts) else { return }
        await withCheckedContinuation { continuation in
            waiters[counts, default: []].append(continuation)
        }
    }
}

private actor OriginRetryCacheReceipt {
    private var initialSnapshotObserved = false
    private var remoteIdentityObserved = false
    private var initialSnapshotWaiters: [CheckedContinuation<Void, Never>] = []
    private var remoteIdentityWaiters: [CheckedContinuation<Void, Never>] = []

    func record(branch: String?, repoEnrichment: RepoEnrichment?) {
        if branch == "main" {
            initialSnapshotObserved = true
            resumeAll(&initialSnapshotWaiters)
        }
        if case .some(.resolvedRemote(_, let raw, let identity, _)) = repoEnrichment,
            raw.origin == "git@github.com:askluna/agent-studio.git",
            identity.groupKey == "remote:askluna/agent-studio"
        {
            remoteIdentityObserved = true
            resumeAll(&remoteIdentityWaiters)
        }
    }

    func waitForInitialSnapshot() async {
        guard !initialSnapshotObserved else { return }
        await withCheckedContinuation { initialSnapshotWaiters.append($0) }
    }

    func waitForRemoteIdentity() async {
        guard !remoteIdentityObserved else { return }
        await withCheckedContinuation { remoteIdentityWaiters.append($0) }
    }

    private func resumeAll(_ waiters: inout [CheckedContinuation<Void, Never>]) {
        let continuations = waiters
        waiters.removeAll(keepingCapacity: false)
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private actor MutableGitWorkingTreeStatusProvider: GitWorkingTreeStatusProvider {
    private var currentStatus: GitWorkingTreeStatus?
    private(set) var callCount = 0
    private var callCountByRootPath: [URL: Int] = [:]
    private var callCountWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    init(status: GitWorkingTreeStatus?) {
        self.currentStatus = status
    }

    func setStatus(_ status: GitWorkingTreeStatus?) {
        currentStatus = status
    }

    func resetRecordedRequests() {
        callCount = 0
        callCountByRootPath.removeAll(keepingCapacity: true)
    }

    func callCount(for rootPath: URL) -> Int {
        callCountByRootPath[rootPath.standardizedFileURL, default: 0]
    }

    func waitForCallCount(_ expectedCount: Int) async {
        guard callCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            callCountWaiters[expectedCount, default: []].append(continuation)
        }
    }

    func statusResult(for rootPath: URL, pathspecs _: [String]?) async -> GitWorkingTreeStatusResult {
        callCount += 1
        callCountByRootPath[rootPath.standardizedFileURL, default: 0] += 1
        resumeSatisfiedCallCountWaiters()
        guard let currentStatus else {
            return .unavailable(GitWorkingTreeStatusUnavailable(reason: .providerReturnedNil))
        }
        return .available(currentStatus)
    }

    private func resumeSatisfiedCallCountWaiters() {
        let satisfiedCounts = callCountWaiters.keys.filter { $0 <= callCount }
        for satisfiedCount in satisfiedCounts {
            let continuations = callCountWaiters.removeValue(forKey: satisfiedCount) ?? []
            for continuation in continuations {
                continuation.resume()
            }
        }
    }
}

private final class SilentFSEventStreamClient: FSEventStreamClient, @unchecked Sendable {
    private let stream: AsyncStream<FSEventBatch>
    private let continuation: AsyncStream<FSEventBatch>.Continuation

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: FSEventBatch.self)
        self.stream = stream
        self.continuation = continuation
    }

    func events() -> AsyncStream<FSEventBatch> {
        stream
    }

    func consumeCoarseRefreshDebt() -> Set<UUID> {
        []
    }

    func register(worktreeId _: UUID, repoId _: UUID, rootPath _: URL) {}

    func unregister(worktreeId _: UUID) {}

    func shutdown() {
        continuation.finish()
    }
}

private actor ObservedFilesystemGitEvents {
    private var filesChangedCountsByWorktreeId: [UUID: Int] = [:]
    private var gitSnapshotCountsByWorktreeId: [UUID: Int] = [:]
    private var latestFilesChangedPathsByWorktreeId: [UUID: [String]] = [:]
    private var seenFilesChangedPathsByWorktreeId: [UUID: Set<String>] = [:]

    func record(_ envelope: RuntimeEnvelope) {
        guard case .worktree(let worktreeEnvelope) = envelope else { return }

        switch worktreeEnvelope.event {
        case .filesystem(.filesChanged(let changeset)):
            filesChangedCountsByWorktreeId[changeset.worktreeId, default: 0] += 1
            latestFilesChangedPathsByWorktreeId[changeset.worktreeId] = changeset.paths
            seenFilesChangedPathsByWorktreeId[changeset.worktreeId, default: []].formUnion(changeset.paths)
        case .gitWorkingDirectory(.snapshotChanged(let snapshot)):
            gitSnapshotCountsByWorktreeId[snapshot.worktreeId, default: 0] += 1
        case .filesystem, .gitWorkingDirectory, .forge, .security:
            return
        }
    }

    func filesChangedCount(for worktreeId: UUID) -> Int {
        filesChangedCountsByWorktreeId[worktreeId, default: 0]
    }

    func gitSnapshotCount(for worktreeId: UUID) -> Int {
        gitSnapshotCountsByWorktreeId[worktreeId, default: 0]
    }

    func latestFilesChangedPaths(for worktreeId: UUID) -> [String]? {
        latestFilesChangedPathsByWorktreeId[worktreeId]
    }

    func hasSeenFilesChangedPath(_ path: String, for worktreeId: UUID) -> Bool {
        seenFilesChangedPathsByWorktreeId[worktreeId]?.contains(path) == true
    }
}
