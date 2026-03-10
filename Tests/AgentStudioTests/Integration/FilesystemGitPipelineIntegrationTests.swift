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
            }
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
        let pane = store.createPane(
            source: .worktree(worktreeId: worktreeId, repoId: repoId),
            title: "Pipeline Pane",
            facets: PaneContextFacets(repoId: repoId, worktreeId: worktreeId, cwd: rootPath)
        )
        let panesById: [UUID: Pane] = [pane.id: pane]
        let worktreeRootsByWorktreeId: [UUID: URL] = [worktreeId: rootPath]

        let paneProjectionStore = PaneFilesystemProjectionStore()
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
                paneProjectionStore.consume(
                    envelope,
                    panesById: panesById,
                    worktreeRootsByWorktreeId: worktreeRootsByWorktreeId
                )
                await observed.record(envelope)
            }
        }
        defer { consumerTask.cancel() }

        await pipeline.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
        await pipeline.enqueueRawPathsForTesting(
            worktreeId: worktreeId,
            paths: ["Sources/Feature.swift"]
        )

        let receivedFilesChanged = await eventually("filesChanged fact should be posted") {
            await observed.filesChangedCount(for: worktreeId) >= 1
        }
        #expect(receivedFilesChanged)

        let receivedGitSnapshot = await eventually("gitSnapshotChanged fact should be posted") {
            await observed.gitSnapshotCount(for: worktreeId) >= 1
        }
        #expect(receivedGitSnapshot)

        let projectionConverged = await eventually("pane filesystem projection should update") {
            paneProjectionStore.snapshotsByPaneId[pane.id]?.changedPaths.contains("Sources/Feature.swift") == true
        }
        #expect(projectionConverged)

        let gitStoreConverged = await eventually("workspace cache enrichment should update") {
            guard let snapshot = repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.snapshot else { return false }
            return snapshot.summary.changed == 2
                && snapshot.summary.staged == 1
                && snapshot.summary.untracked == 1
                && snapshot.branch == "feature/pipeline"
        }
        #expect(gitStoreConverged)

        await pipeline.shutdown()
    }

    @Test("periodic git refresh updates cache sync state without filesystem ingress")
    func periodicGitRefreshUpdatesCacheWithoutFilesystemIngress() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let provider = MutableGitWorkingTreeStatusProvider(
            status: GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(
                    changed: 0,
                    staged: 0,
                    untracked: 0,
                    linesAdded: 0,
                    linesDeleted: 0,
                    aheadCount: 0,
                    behindCount: 0,
                    hasUpstream: true
                ),
                branch: "main",
                origin: "git@github.com:askluna/agent-studio.git"
            )
        )
        let pipeline = FilesystemGitPipeline(
            bus: bus,
            gitWorkingTreeProvider: provider,
            fseventStreamClient: SilentFSEventStreamClient(),
            gitCoalescingWindow: .zero,
            gitPeriodicRefreshInterval: .milliseconds(120)
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
        cacheCoordinator.startConsuming()
        await waitForSubscriber(bus: bus, minimumCount: 1)
        defer { cacheCoordinator.stopConsuming() }

        await pipeline.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)

        let initialSnapshotArrived = await eventually("initial periodic snapshot should arrive") {
            guard let snapshot = repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.snapshot else { return false }
            return snapshot.summary.aheadCount == 0 && snapshot.summary.behindCount == 0
        }
        #expect(initialSnapshotArrived)

        await provider.setStatus(
            GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(
                    changed: 0,
                    staged: 0,
                    untracked: 0,
                    linesAdded: 0,
                    linesDeleted: 0,
                    aheadCount: 1,
                    behindCount: 0,
                    hasUpstream: true
                ),
                branch: "main",
                origin: "git@github.com:askluna/agent-studio.git"
            )
        )

        let aheadUpdateArrived = await eventually("periodic refresh should update ahead count") {
            repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.snapshot?.summary.aheadCount == 1
        }
        #expect(aheadUpdateArrived)

        await provider.setStatus(
            GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(
                    changed: 0,
                    staged: 0,
                    untracked: 0,
                    linesAdded: 0,
                    linesDeleted: 0,
                    aheadCount: 0,
                    behindCount: 2,
                    hasUpstream: true
                ),
                branch: "main",
                origin: "git@github.com:askluna/agent-studio.git"
            )
        )

        let behindUpdateArrived = await eventually("periodic refresh should update behind count") {
            repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.snapshot?.summary.behindCount == 2
        }
        #expect(behindUpdateArrived)

        await pipeline.shutdown()
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
        coordinator.startConsuming()
        await waitForSubscriber(bus: bus, minimumCount: 1)
        defer { coordinator.stopConsuming() }

        await pipeline.register(worktreeId: worktreeId, repoId: repo.id, rootPath: rootPath)

        let initialSnapshotConverged = await eventually(
            "initial registration should produce a git snapshot before origin retry",
            maxAttempts: 1200
        ) {
            repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "main"
        }
        #expect(initialSnapshotConverged)

        await provider.setStatus(status(originResolution: .resolved("git@github.com:askluna/agent-studio.git")))
        await pipeline.enqueueRawPathsForTesting(worktreeId: worktreeId, paths: [".git/config"])

        let remoteIdentityConverged = await eventually(
            "git config change should trigger origin retry and remote identity",
            maxAttempts: 1200
        ) {
            guard case .some(.resolvedRemote(_, let raw, let identity, _)) = repoCache.repoEnrichmentByRepoId[repo.id]
            else {
                return false
            }
            return raw.origin == "git@github.com:askluna/agent-studio.git"
                && identity.groupKey == "remote:askluna/agent-studio"
        }
        #expect(remoteIdentityConverged)

        await pipeline.shutdown()
    }

    private func eventually(
        _ description: String,
        maxAttempts: Int = 200,
        pollIntervalNanoseconds: UInt64 = 10_000_000,
        condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        for _ in 0..<maxAttempts {
            if await condition() {
                return true
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        Issue.record("\(description) timed out")
        return false
    }

    private func waitForSubscriber(
        bus: EventBus<RuntimeEnvelope>,
        minimumCount: Int,
        maxAttempts: Int = 100
    ) async {
        for _ in 0..<maxAttempts {
            if await bus.subscriberCount >= minimumCount {
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        Issue.record("Expected bus subscriber count >= \(minimumCount)")
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

    func record(_ envelope: RuntimeEnvelope) {
        guard case .worktree(let worktreeEnvelope) = envelope else { return }

        switch worktreeEnvelope.event {
        case .filesystem(.filesChanged(let changeset)):
            filesChangedCountsByWorktreeId[changeset.worktreeId, default: 0] += 1
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
}
