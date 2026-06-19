import Foundation
import Testing

@testable import AgentStudio

func makeTestPaneRuntimeEventBus() -> EventBus<RuntimeEnvelope> {
    EventBus(
        replayConfiguration: .init(
            capacityPerSource: 256,
            sourceKey: { envelope in
                envelope.source.description
            }
        )
    )
}

@MainActor
func makeTestWorkspaceSurfaceCoordinator(
    store: WorkspaceStore,
    viewRegistry: ViewRegistry,
    runtime: SessionRuntime,
    surfaceManager: WorkspaceSurfaceManaging,
    runtimeRegistry: RuntimeRegistry,
    paneEventBus: EventBus<RuntimeEnvelope> = makeTestPaneRuntimeEventBus(),
    windowLifecycleStore: WindowLifecycleAtom = WindowLifecycleAtom()
) -> WorkspaceSurfaceCoordinator {
    WorkspaceSurfaceCoordinator(
        store: store,
        viewRegistry: viewRegistry,
        runtime: runtime,
        surfaceManager: surfaceManager,
        runtimeRegistry: runtimeRegistry,
        paneEventBus: paneEventBus,
        windowLifecycleStore: windowLifecycleStore
    )
}

@MainActor
func eventually(
    _ description: String,
    maxTurns: Int = 200,
    condition: @escaping @MainActor () -> Bool
) async {
    for _ in 0..<maxTurns {
        if condition() {
            return
        }
        await Task.yield()
    }
    #expect(condition(), "\(description) timed out")
}
