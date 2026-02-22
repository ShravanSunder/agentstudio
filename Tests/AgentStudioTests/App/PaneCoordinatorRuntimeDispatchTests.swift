import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneCoordinatorRuntimeDispatchTests {
    @Test("dispatchRuntimeCommand resolves pane target centrally")
    func dispatchUsesResolver() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let mockSurfaceManager = MockPaneCoordinatorSurfaceManager()
        let runtimeRegistry = RuntimeRegistry()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: runtimeRegistry
        )

        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/runtime-dispatch")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let fakeRuntime = FakePaneRuntime(paneId: PaneId(uuid: pane.id))
        coordinator.registerRuntime(fakeRuntime)

        let result = await coordinator.dispatchRuntimeCommand(.activate, target: .activePane)
        #expect(result == .success(commandId: fakeRuntime.receivedCommandIds.first!))
        #expect(fakeRuntime.receivedCommands.count == 1)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("dispatchRuntimeCommand fails for unresolved target")
    func dispatchFailsForMissingTarget() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-missing-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let mockSurfaceManager = MockPaneCoordinatorSurfaceManager()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )

        let result = await coordinator.dispatchRuntimeCommand(.activate, target: .activePane)
        #expect(result == .failure(.invalidPayload(description: "Unable to resolve pane target")))

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("closeTab teardown unregisters runtime from registry")
    func closeTab_unregistersRuntime() {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-close-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let mockSurfaceManager = MockPaneCoordinatorSurfaceManager()
        let runtimeRegistry = RuntimeRegistry()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: mockSurfaceManager,
            runtimeRegistry: runtimeRegistry
        )

        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/runtime-close")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "RuntimeClose"), title: "RuntimeClose")
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        let fakeRuntime = FakePaneRuntime(paneId: PaneId(uuid: pane.id))
        coordinator.registerRuntime(fakeRuntime)
        #expect(coordinator.runtimeForPane(PaneId(uuid: pane.id)) != nil)

        coordinator.execute(.closeTab(tabId: tab.id))

        #expect(coordinator.runtimeForPane(PaneId(uuid: pane.id)) == nil)

        try? FileManager.default.removeItem(at: tempDir)
    }
}

@MainActor
private final class FakePaneRuntime: PaneRuntime {
    let paneId: PaneId
    var metadata: PaneMetadata
    var lifecycle: PaneRuntimeLifecycle = .ready
    var capabilities: Set<PaneCapability> = [.input]
    private let stream: AsyncStream<PaneEventEnvelope>

    private(set) var receivedCommands: [PaneCommandEnvelope] = []
    private(set) var receivedCommandIds: [UUID] = []

    init(paneId: PaneId) {
        self.paneId = paneId
        self.metadata = PaneMetadata(source: .floating(workingDirectory: nil, title: "Fake"), title: "Fake")
        self.stream = AsyncStream<PaneEventEnvelope> { continuation in
            continuation.finish()
        }
    }

    func handleCommand(_ envelope: PaneCommandEnvelope) async -> ActionResult {
        receivedCommands.append(envelope)
        receivedCommandIds.append(envelope.commandId)
        return .success(commandId: envelope.commandId)
    }

    func subscribe() -> AsyncStream<PaneEventEnvelope> {
        stream
    }

    func snapshot() -> PaneRuntimeSnapshot {
        PaneRuntimeSnapshot(
            paneId: paneId,
            metadata: metadata,
            lifecycle: lifecycle,
            capabilities: capabilities,
            lastSeq: 0,
            timestamp: Date()
        )
    }

    func eventsSince(seq: UInt64) async -> EventReplayBuffer.ReplayResult {
        EventReplayBuffer.ReplayResult(events: [], nextSeq: seq, gapDetected: false)
    }

    func shutdown(timeout: Duration) async -> [UUID] {
        []
    }
}

@MainActor
private final class MockPaneCoordinatorSurfaceManager: PaneCoordinatorSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>

    init() {
        self.cwdStream = AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { continuation in
            continuation.finish()
        }
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { cwdStream }

    func syncFocus(activeSurfaceId: UUID?) {}

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        .failure(.ghosttyNotInitialized)
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? {
        nil
    }

    func requeueUndo(_ surfaceId: UUID) {}

    func destroy(_ surfaceId: UUID) {}
}
