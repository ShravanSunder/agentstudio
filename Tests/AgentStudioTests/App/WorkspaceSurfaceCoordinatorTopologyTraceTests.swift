import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceSurfaceCoordinatorTopologyTraceTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("closing four Bridge tabs keeps topology lookup telemetry bounded")
    func closeFourBridgeTabsKeepsTopologyLookupTelemetryBounded() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-close-bridge-topology-\(UUID().uuidString)")
        let traceDirectory = temporaryTraceDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            try? FileManager.default.removeItem(at: traceDirectory)
        }
        let runtime = makePerformanceTraceRuntime(traceDirectory: traceDirectory)
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)
        let store = WorkspaceStore()
        let surfaceManager = TopologyTraceSurfaceManager()
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: surfaceManager,
            runtimeRegistry: RuntimeRegistry(),
            paneEventBus: EventBus<RuntimeEnvelope>(),
            filesystemSource: TopologyTraceRecordingFilesystemSource(),
            windowLifecycleStore: WindowLifecycleAtom(),
            performanceTraceRecorder: recorder
        )
        defer { Task { await coordinator.shutdown() } }

        let repo = store.addRepo(at: tempDir.appending(path: "bridge-root"))
        let worktree = try #require(store.repo(repo.id)?.worktrees.single)
        var tabs: [Tab] = []
        for index in 0..<4 {
            let pane = makeCWDOnlyBridgePane(store, title: "Bridge \(index)", cwd: worktree.path)
            let tab = Tab(paneId: pane.id, name: "Bridge \(index)")
            store.appendTab(tab)
            tabs.append(tab)
        }
        store.setActiveTab(tabs[0].id)
        await coordinator.waitForFilesystemRootsAndActivitySyncIdle()

        let repeatedCoordinatorCWD = worktree.path.appending(path: "Sources")
        let sentinelCoordinatorCWD = worktree.path.appending(path: "Tests")
        let tracedPaneID = try #require(tabs[0].activePaneId)
        for _ in 0..<64 {
            surfaceManager.sendCWDChange(paneId: tracedPaneID, cwd: repeatedCoordinatorCWD)
        }
        surfaceManager.sendCWDChange(paneId: tracedPaneID, cwd: sentinelCoordinatorCWD)
        await eventually("coordinator should consume the sentinel CWD change") {
            store.pane(tracedPaneID)?.metadata.cwd == sentinelCoordinatorCWD
        }

        for tab in tabs {
            for _ in 0..<16 {
                _ = store.paneAtom.panes
            }
            coordinator.execute(.closeTab(tabId: tab.id))
        }
        coordinator.undoCloseTab()
        for _ in 0..<16 {
            _ = store.paneAtom.panes
        }
        try await recorder.drain()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(countOccurrences(of: "\"body\":\"performance.topology.repo_and_worktree\"", in: contents) == 2)
        await coordinator.shutdown()
    }

    private func makeCWDOnlyBridgePane(
        _ store: WorkspaceStore,
        title: String,
        cwd: URL
    ) -> Pane {
        store.createPane(
            content: .bridgePanel(
                BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(rootPath: cwd.path, baseline: .localDefaultBranch(branchName: "main"))
                )
            ),
            metadata: PaneMetadata(
                contentType: .diff,
                launchDirectory: cwd,
                title: title,
                facets: PaneContextFacets(cwd: cwd)
            )
        )
    }

    private func makePerformanceTraceRuntime(traceDirectory: URL) -> AgentStudioTraceRuntime {
        AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "close-bridge-topology-lookup",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 918,
            timeUnixNano: { 918 }
        )
    }

    private func countOccurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private func temporaryTraceDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-close-bridge-topology-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private actor TopologyTraceRecordingFilesystemSource: WorkspaceFilesystemSourceManaging {
    private(set) var registeredRoots: [UUID: URL] = [:]
    private(set) var activityByWorktreeId: [UUID: Bool] = [:]
    private(set) var activePaneWorktreeId: UUID?

    func start() async {}

    func shutdown() async {}

    func register(worktreeId: UUID, repoId _: UUID, rootPath: URL) async {
        registeredRoots[worktreeId] = rootPath
    }

    func unregister(worktreeId: UUID) async {
        registeredRoots.removeValue(forKey: worktreeId)
        activityByWorktreeId.removeValue(forKey: worktreeId)
        if activePaneWorktreeId == worktreeId {
            activePaneWorktreeId = nil
        }
    }

    func assertTopology(_ assertion: FilesystemTopologyAssertion) async {
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

}

private final class TopologyTraceSurfaceManager: WorkspaceSurfaceManaging {
    private let cwdContinuation: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>.Continuation
    let surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>

    init() {
        let stream = AsyncStream.makeStream(of: SurfaceManager.SurfaceCWDChangeEvent.self)
        self.surfaceCWDChanges = stream.stream
        self.cwdContinuation = stream.continuation
    }

    func sendCWDChange(paneId: UUID, cwd: URL) {
        cwdContinuation.yield(
            SurfaceManager.SurfaceCWDChangeEvent(surfaceId: UUID(), paneId: paneId, cwd: cwd)
        )
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
