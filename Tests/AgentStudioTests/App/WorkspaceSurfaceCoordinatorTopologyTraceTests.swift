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
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore(persistor: persistor)
        store.restore()
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: TopologyTraceSurfaceManager(),
            runtimeRegistry: RuntimeRegistry(),
            paneEventBus: EventBus<RuntimeEnvelope>(),
            filesystemSource: TopologyTraceRecordingFilesystemSource(),
            paneFilesystemProjectionStore: PaneFilesystemProjectionAtom(),
            windowLifecycleStore: WindowLifecycleAtom()
        )
        defer {
            Task { await coordinator.shutdown() }
            try? FileManager.default.removeItem(at: tempDir)
        }

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

        let traceDirectory = temporaryTraceDirectoryURL()
        let runtime = makePerformanceTraceRuntime(traceDirectory: traceDirectory)
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)
        store.repositoryTopologyAtom.setPerformanceTraceRecorder(recorder)

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
        #expect(countOccurrences(of: "\"body\":\"performance.topology.repo_and_worktree\"", in: contents) == 1)
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

    func start() {}

    func shutdown() {}

    func register(worktreeId: UUID, repoId _: UUID, rootPath: URL) {
        registeredRoots[worktreeId] = rootPath
    }

    func unregister(worktreeId: UUID) {
        registeredRoots.removeValue(forKey: worktreeId)
        activityByWorktreeId.removeValue(forKey: worktreeId)
        if activePaneWorktreeId == worktreeId {
            activePaneWorktreeId = nil
        }
    }

    func assertTopology(_ assertion: FilesystemTopologyAssertion) {
        let desiredWorktreeIds = Set(assertion.contextsByWorktreeId.keys)
        registeredRoots = assertion.contextsByWorktreeId.mapValues(\.rootPath)
        activityByWorktreeId = activityByWorktreeId.filter { desiredWorktreeIds.contains($0.key) }
        if let activePaneWorktreeId, !desiredWorktreeIds.contains(activePaneWorktreeId) {
            self.activePaneWorktreeId = nil
        }
    }

    func setActivity(worktreeId: UUID, isActiveInApp: Bool) {
        activityByWorktreeId[worktreeId] = isActiveInApp
    }

    func setActivePaneWorktree(worktreeId: UUID?) {
        activePaneWorktreeId = worktreeId
    }

}

private final class TopologyTraceSurfaceManager: WorkspaceSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>

    init() {
        self.cwdStream = AsyncStream { continuation in
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
