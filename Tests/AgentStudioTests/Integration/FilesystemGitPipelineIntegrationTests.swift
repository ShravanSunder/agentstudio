import Foundation
import Testing

@testable import AgentStudio

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
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: workspaceDir))
        store.restore()
        let repoCache = WorkspaceRepoCache()
        let cacheCoordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: store,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        let observed = ObservedFilesystemGitEvents()

        let stream = await bus.subscribe()
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
            await observed.latestFilesChangedPaths(for: worktreeId)?.contains("Sources/Feature.swift") == true
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
            gitPeriodicRefreshInterval: .milliseconds(120),
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
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: workspaceDir))
        store.restore()

        let repoCache = WorkspaceRepoCache()
        let cacheCoordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: store,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        let coordinatorStream = await bus.subscribe()
        let coordinatorTask = Task { @MainActor in
            for await envelope in coordinatorStream {
                cacheCoordinator.consume(envelope)
            }
        }
        await waitForSubscriberCount(bus: bus, atLeast: 3)
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

        await provider.setStatus(makeTrackedStatus(aheadCount: 1))
        gitClock.advance(by: .milliseconds(120))

        let aheadUpdateArrived = await eventually("periodic refresh should update ahead count") {
            repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.snapshot?.summary.aheadCount == 1
        }
        #expect(aheadUpdateArrived)
        let secondRefreshSleepScheduled = await waitUntilYielding {
            gitClock.pendingSleepCount > 0
        }
        #expect(secondRefreshSleepScheduled)

        await provider.setStatus(makeTrackedStatus(behindCount: 2))
        gitClock.advance(by: .milliseconds(120))

        let behindUpdateArrived = await eventually("periodic refresh should update behind count") {
            repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.snapshot?.summary.behindCount == 2
        }
        #expect(behindUpdateArrived)

        await shutdownWorld(
            pipeline: pipeline,
            observerTasks: [coordinatorTask],
            bus: bus
        )
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
        let workspaceStore = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: workspaceDir))
        workspaceStore.restore()
        let repo = workspaceStore.addRepo(at: rootPath)
        guard let worktreeId = repo.worktrees.first?.id else {
            Issue.record("Expected repo to have main worktree")
            await pipeline.shutdown()
            return
        }

        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        let coordinatorStream = await bus.subscribe()
        let coordinatorTask = Task { @MainActor in
            for await envelope in coordinatorStream {
                coordinator.consume(envelope)
            }
        }
        await waitForSubscriberCount(bus: bus, atLeast: 3)
        await pipeline.register(worktreeId: worktreeId, repoId: repo.id, rootPath: rootPath)

        let initialSnapshotConverged = await eventually(
            "initial registration should produce a git snapshot before origin retry",
            maxTurns: 20_000
        ) {
            repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "main"
        }
        #expect(initialSnapshotConverged)

        await provider.setStatus(status(originResolution: .resolved("git@github.com:askluna/agent-studio.git")))
        await pipeline.enqueueRawPathsForTesting(worktreeId: worktreeId, paths: [".git/config"])

        let remoteIdentityConverged = await eventually(
            "git config change should trigger origin retry and remote identity",
            maxTurns: 20_000
        ) {
            guard case .some(.resolvedRemote(_, let raw, let identity, _)) = repoCache.repoEnrichmentByRepoId[repo.id]
            else {
                return false
            }
            return raw.origin == "git@github.com:askluna/agent-studio.git"
                && identity.groupKey == "remote:askluna/agent-studio"
        }
        #expect(remoteIdentityConverged)

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

private actor MutableGitWorkingTreeStatusProvider: GitWorkingTreeStatusProvider {
    private var currentStatus: GitWorkingTreeStatus?

    init(status: GitWorkingTreeStatus?) {
        self.currentStatus = status
    }

    func setStatus(_ status: GitWorkingTreeStatus?) {
        currentStatus = status
    }

    func status(for _: URL) async -> GitWorkingTreeStatus? {
        currentStatus
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

    func record(_ envelope: RuntimeEnvelope) {
        guard case .worktree(let worktreeEnvelope) = envelope else { return }

        switch worktreeEnvelope.event {
        case .filesystem(.filesChanged(let changeset)):
            filesChangedCountsByWorktreeId[changeset.worktreeId, default: 0] += 1
            latestFilesChangedPathsByWorktreeId[changeset.worktreeId] = changeset.paths
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
}
