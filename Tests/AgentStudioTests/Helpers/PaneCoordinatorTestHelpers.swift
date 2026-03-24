import Foundation
import Testing

@testable import AgentStudio

@MainActor
func makeTestPaneCoordinator(
    store: WorkspaceStore,
    viewRegistry: ViewRegistry,
    runtime: SessionRuntime,
    surfaceManager: PaneCoordinatorSurfaceManaging,
    runtimeRegistry: RuntimeRegistry
) -> PaneCoordinator {
    PaneCoordinator(
        store: store,
        viewRegistry: viewRegistry,
        runtime: runtime,
        surfaceManager: surfaceManager,
        runtimeRegistry: runtimeRegistry,
        windowLifecycleStore: WindowLifecycleStore()
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
