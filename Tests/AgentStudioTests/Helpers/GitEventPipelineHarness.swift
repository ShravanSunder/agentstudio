import Foundation
import GhosttyKit

@testable import AgentStudio

final class MockPaneCoordinatorSurfaceManagerForHarness: PaneCoordinatorSurfaceManaging {
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
        .failure(.operationFailed("mock"))
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        _ = surfaceId
        _ = paneId
        return nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {
        _ = surfaceId
        _ = reason
    }

    func undoClose() -> ManagedSurface? { nil }

    func requeueUndo(_ surfaceId: UUID) {
        _ = surfaceId
    }

    func destroy(_ surfaceId: UUID) {
        _ = surfaceId
    }
}

actor RecordingFilesystemSourceHarness: PaneCoordinatorFilesystemSourceManaging {
    private var registeredRoots: [UUID: URL] = [:]
    private var activityByWorktreeId: [UUID: Bool] = [:]
    private var activePaneWorktreeId: UUID?
    private var registerLog: [(worktreeId: UUID, repoId: UUID, rootPath: URL)] = []
    private var unregisterLog: [UUID] = []

    func start() async {}

    func shutdown() async {}

    func register(worktreeId: UUID, repoId: UUID, rootPath: URL) async {
        registeredRoots[worktreeId] = rootPath
        registerLog.append((worktreeId: worktreeId, repoId: repoId, rootPath: rootPath))
    }

    func unregister(worktreeId: UUID) async {
        registeredRoots.removeValue(forKey: worktreeId)
        unregisterLog.append(worktreeId)
        activityByWorktreeId.removeValue(forKey: worktreeId)
        if activePaneWorktreeId == worktreeId {
            activePaneWorktreeId = nil
        }
    }

    func setActivity(worktreeId: UUID, isActiveInApp: Bool) async {
        activityByWorktreeId[worktreeId] = isActiveInApp
    }

    func setActivePaneWorktree(worktreeId: UUID?) async {
        activePaneWorktreeId = worktreeId
    }

    func snapshot() -> FilesystemSourceHarnessSnapshot {
        FilesystemSourceHarnessSnapshot(
            registeredRoots: registeredRoots,
            activityByWorktreeId: activityByWorktreeId,
            activePaneWorktreeId: activePaneWorktreeId,
            registerLog: registerLog,
            unregisterLog: unregisterLog
        )
    }
}

struct FilesystemSourceHarnessSnapshot: Sendable {
    let registeredRoots: [UUID: URL]
    let activityByWorktreeId: [UUID: Bool]
    let activePaneWorktreeId: UUID?
    let registerLog: [(worktreeId: UUID, repoId: UUID, rootPath: URL)]
    let unregisterLog: [UUID]
}

final class ControllableGroupedWatchedFolderScanner: @unchecked Sendable {
    private let lock = NSLock()
    private var resultsByRoot: [URL: [RepoScanner.RepoScanGroup]] = [:]

    func setResults(_ resultsByRoot: [URL: [RepoScanner.RepoScanGroup]]) {
        lock.withLock {
            self.resultsByRoot = Dictionary(
                uniqueKeysWithValues: resultsByRoot.map { key, value in
                    (
                        key.standardizedFileURL,
                        value.map { group in
                            RepoScanner.RepoScanGroup(
                                clonePath: group.clonePath.standardizedFileURL,
                                linkedWorktreePaths: group.linkedWorktreePaths.map(\.standardizedFileURL)
                            )
                        }
                    )
                }
            )
        }
    }

    func scan(_ root: URL) -> [RepoScanner.RepoScanGroup] {
        lock.withLock {
            resultsByRoot[root.standardizedFileURL, default: []]
        }
    }
}

@MainActor
struct GitTopologyPipelineHarness {
    let bus: EventBus<RuntimeEnvelope>
    let workspaceStore: WorkspaceStore
    let repoCache: WorkspaceRepoCache
    let coordinator: WorkspaceCacheCoordinator
    let paneCoordinator: PaneCoordinator
    let discoveryActor: FilesystemActor
    let scanner: ControllableGroupedWatchedFolderScanner
    let fseventClient: ControllableFSEventStreamClient
    let filesystemSource: RecordingFilesystemSourceHarness
    let tempDir: URL

    static func make() async -> Self {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "git-topology-harness-\(UUID().uuidString)")
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = WorkspaceStore(
            persistor: WorkspacePersistor(workspacesDir: tempDir)
        )
        workspaceStore.restore()
        let repoCache = WorkspaceRepoCache()
        let scanner = ControllableGroupedWatchedFolderScanner()
        let fseventClient = ControllableFSEventStreamClient()
        let discoveryActor = FilesystemActor(
            bus: bus,
            fseventStreamClient: fseventClient,
            groupedWatchedFolderScanner: scanner.scan,
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )
        let filesystemSource = RecordingFilesystemSourceHarness()
        let paneCoordinator = PaneCoordinator(
            store: workspaceStore,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: workspaceStore),
            surfaceManager: MockPaneCoordinatorSurfaceManagerForHarness(),
            runtimeRegistry: RuntimeRegistry(),
            paneEventBus: bus,
            filesystemSource: filesystemSource,
            paneFilesystemProjectionStore: PaneFilesystemProjectionStore(),
            windowLifecycleStore: WindowLifecycleStore()
        )
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            topologyEffectHandler: paneCoordinator,
            scopeSyncHandler: { _ in }
        )
        coordinator.startConsuming()

        return Self(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            coordinator: coordinator,
            paneCoordinator: paneCoordinator,
            discoveryActor: discoveryActor,
            scanner: scanner,
            fseventClient: fseventClient,
            filesystemSource: filesystemSource,
            tempDir: tempDir
        )
    }

    func shutdown() async {
        await coordinator.shutdown()
        await paneCoordinator.shutdown()
        await discoveryActor.shutdown()
        try? FileManager.default.removeItem(at: tempDir)
    }

    @discardableResult
    func refreshWatchedFolders(_ paths: [URL]) async -> WatchedFolderRefreshSummary {
        await discoveryActor.refreshWatchedFolders(paths)
    }

    func postTopology(_ event: TopologyEvent, source: SystemSource = .builtin(.filesystemWatcher)) async {
        _ = await bus.post(
            RuntimeEnvelopeHarness.topologyEnvelope(
                event: event,
                source: source
            )
        )
    }

    func filesystemSnapshot() async -> FilesystemSourceHarnessSnapshot {
        await filesystemSource.snapshot()
    }
}

@MainActor
struct GitEnrichmentPipelineHarness {
    let bus: EventBus<RuntimeEnvelope>
    let workspaceStore: WorkspaceStore
    let repoCache: WorkspaceRepoCache
    let coordinator: WorkspaceCacheCoordinator
    let projector: GitWorkingDirectoryProjector
    let forgeActor: ForgeActor
    let tempDir: URL

    static func make(
        gitProvider: some GitWorkingTreeStatusProvider,
        forgeProvider: some ForgeStatusProvider
    ) async -> Self {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "git-enrichment-harness-\(UUID().uuidString)")
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = WorkspaceStore(
            persistor: WorkspacePersistor(workspacesDir: tempDir)
        )
        workspaceStore.restore()
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        let projector = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: gitProvider,
            coalescingWindow: .zero
        )
        let forgeActor = ForgeActor(
            bus: bus,
            statusProvider: forgeProvider,
            providerName: "stub",
            pollInterval: .seconds(60)
        )
        coordinator.startConsuming()
        return Self(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            coordinator: coordinator,
            projector: projector,
            forgeActor: forgeActor,
            tempDir: tempDir
        )
    }

    func start() async {
        await projector.start()
        await forgeActor.start()
    }

    func shutdown() async {
        await coordinator.shutdown()
        await projector.shutdown()
        await forgeActor.shutdown()
        try? FileManager.default.removeItem(at: tempDir)
    }
}
