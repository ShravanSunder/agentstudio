import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneCoordinatorTests {
    private struct PaneCoordinatorHarness {
        let coordinator: PaneCoordinator
        let tempDir: URL
    }

    private func makeHarnessCoordinator() -> PaneCoordinatorHarness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore(persistor: persistor)
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let coordinator = PaneCoordinator(store: store, viewRegistry: viewRegistry, runtime: runtime)
        return PaneCoordinatorHarness(
            coordinator: coordinator,
            tempDir: tempDir
        )
    }

    @Test
    func test_paneCoordinator_exposesExecuteAPI() async {
        let harness = makeHarnessCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let action: PaneAction = .selectTab(tabId: UUID())
        harness.coordinator.execute(action)
    }
}
