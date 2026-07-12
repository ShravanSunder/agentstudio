import Foundation

@testable import AgentStudio

@MainActor
struct WorkspaceSurfaceCoordinatorViewFactoryHarness {
    let store: WorkspaceStore
    let viewRegistry: ViewRegistry
    let runtime: SessionRuntime
    let coordinator: WorkspaceSurfaceCoordinator
    let tempDir: URL
}

@MainActor
func makeWorkspaceSurfaceCoordinatorViewFactoryHarness(
    paneEventBus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared
) -> WorkspaceSurfaceCoordinatorViewFactoryHarness {
    let tempDir = FileManager.default.temporaryDirectory
        .appending(path: "agentstudio-coordinator-tests-\(UUID().uuidString)")
    let persistor = WorkspacePersistor(workspacesDir: tempDir)
    let store = WorkspaceStore(persistor: persistor)
    store.restore()
    let viewRegistry = ViewRegistry()
    let runtime = SessionRuntime(store: store)
    let coordinator = WorkspaceSurfaceCoordinator(
        store: store,
        viewRegistry: viewRegistry,
        runtime: runtime,
        surfaceManager: SurfaceManager.shared,
        runtimeRegistry: .shared,
        paneEventBus: paneEventBus,
        windowLifecycleStore: WindowLifecycleAtom()
    )
    return WorkspaceSurfaceCoordinatorViewFactoryHarness(
        store: store,
        viewRegistry: viewRegistry,
        runtime: runtime,
        coordinator: coordinator,
        tempDir: tempDir
    )
}

@MainActor
func makeBridgeReplayEnvelope(paneId: PaneId, sequence: UInt64) -> RuntimeEnvelope {
    makeRuntimeEnvelope(
        source: .pane(paneId),
        paneKind: .diff,
        seq: sequence,
        commandId: nil,
        correlationId: nil,
        timestamp: ContinuousClock().now,
        epoch: 0,
        event: .lifecycle(.surfaceCreated)
    )
}
