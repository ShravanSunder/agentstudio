import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct TerminalPaneMountViewExitBehaviorTests {
    private struct PaneTabControllerHarness {
        let store: WorkspaceStore
        let controller: PaneTabViewController
        let tempDir: URL
    }

    private func makePaneTabControllerHarness() -> PaneTabControllerHarness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-terminal-exit-tests-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let surfaceManager = MockTerminalExitSurfaceManager()
        let coordinator = makeTestPaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: surfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )
        let executor = ActionExecutor(coordinator: coordinator, store: store)
        let applicationLifecycleMonitor = ApplicationLifecycleMonitor(
            appLifecycleStore: AppLifecycleStore(),
            windowLifecycleStore: WindowLifecycleStore()
        )
        let controller = PaneTabViewController(
            store: store,
            repoCache: WorkspaceRepoCache(),
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            executor: executor,
            tabBarAdapter: TabBarAdapter(store: store, repoCache: WorkspaceRepoCache()),
            viewRegistry: viewRegistry
        )
        return PaneTabControllerHarness(
            store: store,
            controller: controller,
            tempDir: tempDir
        )
    }

    private func makeProcessExitMountView() -> TerminalPaneMountView {
        let paneId = UUID()
        return TerminalPaneMountView(paneId: paneId, title: "Terminal")
    }

    @Test("process termination suppresses the competing process-exited overlay")
    func processTermination_suppressesProcessExitedOverlay() {
        let mountView = makeProcessExitMountView()

        mountView.handleProcessTerminated()
        #expect(mountView.isProcessRunning == false)

        mountView.applyHealthUpdateForTesting(.processExited(exitCode: nil))

        #expect(!mountView.isShowingErrorOverlayForTesting)
    }

    @Test("fatal terminal errors still show the error overlay after termination")
    func fatalTerminalError_stillShowsErrorOverlayAfterTermination() {
        let mountView = makeProcessExitMountView()

        mountView.handleProcessTerminated()
        mountView.applyHealthUpdateForTesting(.dead)

        #expect(mountView.isShowingErrorOverlayForTesting)
    }

    @Test("terminal process termination closes a single-pane tab")
    func terminalProcessTermination_closesSinglePaneTab() {
        let harness = makePaneTabControllerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/\(UUID().uuidString)")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Solo"), title: "Solo")
        )
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)

        harness.controller.handleTerminalProcessTerminated(paneId: pane.id)

        #expect(harness.store.tabs.isEmpty)
    }
}

@MainActor
private final class MockTerminalExitSurfaceManager: PaneCoordinatorSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>

    init() {
        cwdStream = AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { continuation in
            continuation.finish()
        }
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { cwdStream }

    func syncFocus(activeSurfaceId _: UUID?) {}

    func createSurface(
        config _: Ghostty.SurfaceConfiguration,
        metadata _: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        .failure(.ghosttyNotInitialized)
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        _ = surfaceId
        _ = paneId
        return nil
    }

    func detach(_ surfaceId: UUID, reason _: SurfaceDetachReason) {
        _ = surfaceId
    }

    func undoClose() -> ManagedSurface? {
        nil
    }

    func requeueUndo(_ surfaceId: UUID) {
        _ = surfaceId
    }

    func destroy(_ surfaceId: UUID) {
        _ = surfaceId
    }
}
