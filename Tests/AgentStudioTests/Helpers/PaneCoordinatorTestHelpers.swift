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
func makeTestPaneCoordinator(
    store: WorkspaceStore,
    viewRegistry: ViewRegistry,
    runtime: SessionRuntime,
    surfaceManager: PaneCoordinatorSurfaceManaging,
    runtimeRegistry: RuntimeRegistry,
    paneEventBus: EventBus<RuntimeEnvelope> = makeTestPaneRuntimeEventBus(),
    windowLifecycleStore: WindowLifecycleAtom = WindowLifecycleAtom()
) -> PaneCoordinator {
    PaneCoordinator(
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
