import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

final class HarnessSurfaceManager: WorkspaceSurfaceManaging {
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

actor RecordingFilesystemSourceHarness: WorkspaceFilesystemSourceManaging {
    private var registeredRoots: [UUID: URL] = [:]
    private var activityByWorktreeId: [UUID: Bool] = [:]
    private var activePaneWorktreeId: UUID?
    private var topologyAssertionGeneration: UInt64?
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

    func assertTopology(_ assertion: FilesystemTopologyAssertion) async {
        guard topologyAssertionGeneration.map({ assertion.generation >= $0 }) ?? true else { return }
        topologyAssertionGeneration = assertion.generation
        let desiredWorktreeIds = Set(assertion.contextsByWorktreeId.keys)
        registeredRoots = assertion.contextsByWorktreeId.mapValues(\.rootPath)
        activityByWorktreeId = activityByWorktreeId.filter { desiredWorktreeIds.contains($0.key) }
        if let activePaneWorktreeId, !desiredWorktreeIds.contains(activePaneWorktreeId) {
            self.activePaneWorktreeId = nil
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

final class ControllableWatchedFolderScanSchedulerResults: @unchecked Sendable {
    private let lock = NSLock()
    private var resultsByWatchedPathID: [UUID: [RepoScanner.RepoScanGroup]] = [:]

    func setResults(_ resultsByWatchedPath: [WatchedPath: [RepoScanner.RepoScanGroup]]) {
        lock.withLock {
            resultsByWatchedPathID = Dictionary(
                uniqueKeysWithValues: resultsByWatchedPath.map { watchedPath, groups in
                    (
                        watchedPath.id,
                        groups.map { group in
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

    func makeScheduler() -> WatchedFolderScanScheduler {
        do {
            return try WatchedFolderScanScheduler(
                maximumConcurrentScans: 1,
                now: { .zero },
                validationExecutor: RepoScannerValidationExecutor(
                    validationClient: HarnessUnusedRepoDiscoveryReadClient()
                ),
                sessionFactory: { request, _ in
                    self.makeSession(for: request)
                }
            )
        } catch {
            preconditionFailure("invalid topology harness scheduler configuration: \(error)")
        }
    }

    private func makeSession(
        for request: WatchedFolderScanRequest
    ) -> WatchedFolderScannerSessionPort {
        let result = authoritativeResult(for: request.sourceID.rootID)
        return WatchedFolderScannerSessionPort(
            id: RepoScannerSessionID(rawValue: UUIDv7.generate()),
            advanceOneQuantum: { .finished(result) },
            cancel: { .alreadyFinished },
            consumeValidationCompletion: { _ in .rejected(.sessionFinished) }
        )
    }

    private func authoritativeResult(for watchedPathID: UUID) -> RepoScannerResult {
        guard let groups = lock.withLock({ resultsByWatchedPathID[watchedPathID] }) else {
            Issue.record(
                "topology harness has no configured result for watched path \(watchedPathID)"
            )
            return .failed(
                FailedRepoScan(
                    reason: .scannerServiceFailed(
                        detail: "missing controlled watched-folder result"
                    ),
                    counts: RepoScannerEvidenceCounts(
                        directoryVisitCount: 0,
                        directoryTraversalFailureCount: 0,
                        entryMetadataFailureCount: 0,
                        gitCandidateCount: 0,
                        validationSuccessCount: 0,
                        validationAuthoritativeNegativeCount: 0,
                        validationTimeoutCount: 0,
                        validationCancellationCount: 0,
                        validationFailureCount: 1,
                        scannerServiceInvocationCount: 1
                    ),
                    serviceMetrics: .zero
                )
            )
        }
        let verifiedEntries = groups.flatMap { group in
            let repositoryKey = group.clonePath.standardizedFileURL.path
            return [
                RepoScanner.ResolvedGitEntry(
                    path: group.clonePath,
                    kind: .cloneRoot,
                    repositoryKey: repositoryKey
                )
            ]
                + group.linkedWorktreePaths.map { linkedWorktreePath in
                    RepoScanner.ResolvedGitEntry(
                        path: linkedWorktreePath,
                        kind: .linkedWorktree(parentClonePath: group.clonePath),
                        repositoryKey: repositoryKey
                    )
                }
        }
        return .completeAuthoritative(
            CompleteRepoScan(
                verifiedEntries: verifiedEntries,
                counts: RepoScannerEvidenceCounts(
                    directoryVisitCount: 0,
                    directoryTraversalFailureCount: 0,
                    entryMetadataFailureCount: 0,
                    gitCandidateCount: verifiedEntries.count,
                    validationSuccessCount: verifiedEntries.count,
                    validationAuthoritativeNegativeCount: 0,
                    validationTimeoutCount: 0,
                    validationCancellationCount: 0,
                    validationFailureCount: 0,
                    scannerServiceInvocationCount: 1
                ),
                serviceMetrics: .zero
            )
        )
    }

}

private struct HarnessUnusedRepoDiscoveryReadClient: RepoDiscoveryReadClient {
    func validateDiscoveryCandidate(at candidateURL: URL) async -> GitRepositoryDiscoveryOutcome {
        .failure(.serviceFailed(detail: "unexpected harness validation request for \(candidateURL.path)"))
    }
}

@MainActor
struct GitTopologyPipelineHarness {
    let bus: EventBus<RuntimeEnvelope>
    let workspaceStore: WorkspaceStore
    let repoCache: RepoCacheAtom
    let coordinator: WorkspaceCacheCoordinator
    let workspaceSurfaceCoordinator: WorkspaceSurfaceCoordinator
    let discoveryActor: FilesystemActor
    let scanResults: ControllableWatchedFolderScanSchedulerResults
    let fseventClient: ControllableFSEventStreamClient
    let filesystemSource: RecordingFilesystemSourceHarness
    let tempDir: URL

    static func make() async -> Self {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "git-topology-harness-\(UUID().uuidString)")
        let bus = EventBus<RuntimeEnvelope>()
        let workspaceStore = WorkspaceStore()
        let repoCache = RepoCacheAtom()
        let scanResults = ControllableWatchedFolderScanSchedulerResults()
        let fseventClient = ControllableFSEventStreamClient()
        let discoveryActor = FilesystemActor(
            bus: bus,
            fseventStreamClient: fseventClient,
            watchedFolderScanScheduler: scanResults.makeScheduler(),
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )
        let filesystemSource = RecordingFilesystemSourceHarness()
        let workspaceSurfaceCoordinator = WorkspaceSurfaceCoordinator(
            store: workspaceStore,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: workspaceStore),
            surfaceManager: HarnessSurfaceManager(),
            runtimeRegistry: RuntimeRegistry(),
            paneEventBus: bus,
            filesystemSource: filesystemSource,
            windowLifecycleStore: WindowLifecycleAtom()
        )
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            topologyEffectHandler: workspaceSurfaceCoordinator,
            scopeSyncHandler: { _ in }
        )
        coordinator.startConsuming()

        return Self(
            bus: bus,
            workspaceStore: workspaceStore,
            repoCache: repoCache,
            coordinator: coordinator,
            workspaceSurfaceCoordinator: workspaceSurfaceCoordinator,
            discoveryActor: discoveryActor,
            scanResults: scanResults,
            fseventClient: fseventClient,
            filesystemSource: filesystemSource,
            tempDir: tempDir
        )
    }

    func shutdown() async {
        await coordinator.shutdown()
        await workspaceSurfaceCoordinator.shutdown()
        await discoveryActor.shutdown()
        try? FileManager.default.removeItem(at: tempDir)
    }

    @discardableResult
    func refreshWatchedFolders(_ watchedPaths: [WatchedPath]) async -> WatchedFolderRefreshSummary {
        for watchedPath in watchedPaths {
            do {
                try FileManager.default.createDirectory(
                    at: watchedPath.path,
                    withIntermediateDirectories: true
                )
            } catch {
                preconditionFailure(
                    "topology harness could not create watched root \(watchedPath.path.path): \(error)"
                )
            }
        }
        return await discoveryActor.refreshWatchedFolders(watchedPaths)
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
    let repoCache: RepoCacheAtom
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
        let workspaceStore = WorkspaceStore()
        let repoCache = RepoCacheAtom()
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
