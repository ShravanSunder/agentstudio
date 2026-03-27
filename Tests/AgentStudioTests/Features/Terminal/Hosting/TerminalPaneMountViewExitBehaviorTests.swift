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

    private func waitForAppEventBusSubscriber(countGreaterThan baseline: Int) async {
        for _ in 0..<200 {
            if await AppEventBus.shared.subscriberCount > baseline {
                return
            }
            await Task.yield()
        }
        Issue.record("Timed out waiting for PaneTabViewController to subscribe to AppEventBus")
    }

    private func makeSubscribedPaneTabControllerHarness() async -> PaneTabControllerHarness {
        let harness = makePaneTabControllerHarness()
        let baselineSubscriberCount = await AppEventBus.shared.subscriberCount
        _ = harness.controller.view
        await waitForAppEventBusSubscriber(countGreaterThan: baselineSubscriberCount)
        return harness
    }

    private func makeProcessExitMountView(
        showsRestorePresentationDuringStartup: Bool = false
    ) -> TerminalPaneMountView {
        let paneId = UUID()
        return TerminalPaneMountView(
            restoredSurfaceId: UUID(),
            paneId: paneId,
            title: "Terminal",
            showsRestorePresentationDuringStartup: showsRestorePresentationDuringStartup
        )
    }

    @Test("process termination without subscribers keeps a visible fallback")
    func processTermination_withoutSubscribers_showsFallbackOverlay() async {
        let mountView = makeProcessExitMountView()

        mountView.simulateSurfaceCloseForTesting(processAlive: false)
        #expect(mountView.isProcessRunning == false)

        await eventually("fallback overlay should become visible when the close event is dropped") {
            mountView.isShowingErrorOverlayForTesting
        }

        mountView.applyHealthUpdateForTesting(.processExited(exitCode: nil))

        #expect(mountView.isShowingErrorOverlayForTesting)
    }

    @Test("process termination with subscribers suppresses the competing process-exited overlay")
    func processTermination_withSubscribers_suppressesProcessExitedOverlay() async {
        let harness = await makeSubscribedPaneTabControllerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let mountView = makeProcessExitMountView()

        mountView.simulateSurfaceCloseForTesting(processAlive: false)

        await eventually("close event should be observed by a subscriber") {
            mountView.isProcessExitedOverlaySuppressedAfterTerminationForTesting
        }

        mountView.applyHealthUpdateForTesting(.processExited(exitCode: nil))

        #expect(mountView.isProcessRunning == false)
        #expect(!mountView.isShowingErrorOverlayForTesting)
    }

    @Test("startup restore close with subscribers auto-closes without showing process-exit UI")
    func startupRestoreClose_withSubscribersAutoClosesWithoutProcessExitedUI() async {
        let harness = await makeSubscribedPaneTabControllerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let mountView = makeProcessExitMountView(showsRestorePresentationDuringStartup: true)

        mountView.beginRestorePresentationForTesting()
        #expect(mountView.isShowingStartupOverlayForTesting)

        mountView.simulateSurfaceCloseForTesting(processAlive: false)

        await eventually("startup close should be observed by a subscriber") {
            mountView.isProcessExitedOverlaySuppressedAfterTerminationForTesting
        }

        mountView.applyHealthUpdateForTesting(.processExited(exitCode: nil))

        #expect(mountView.isProcessRunning == false)
        #expect(!mountView.isShowingStartupOverlayForTesting)
        #expect(!mountView.isShowingErrorOverlayForTesting)
    }

    @Test("fatal terminal errors still show the error overlay during startup restore")
    func fatalTerminalError_stillShowsErrorOverlayDuringStartupRestore() {
        let mountView = makeProcessExitMountView(showsRestorePresentationDuringStartup: true)

        mountView.beginRestorePresentationForTesting()
        #expect(mountView.isShowingStartupOverlayForTesting)

        mountView.applyHealthUpdateForTesting(.dead)

        #expect(mountView.isShowingErrorOverlayForTesting)
    }

    @Test("terminal process termination delivered through AppEventBus closes a single-pane tab")
    func terminalProcessTermination_deliveredThroughAppEventBus_closesSinglePaneTab() async {
        let harness = makePaneTabControllerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let baselineSubscriberCount = await AppEventBus.shared.subscriberCount
        _ = harness.controller.view

        let pane = harness.store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/\(UUID().uuidString)")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Solo"), title: "Solo")
        )
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)

        await waitForAppEventBusSubscriber(countGreaterThan: baselineSubscriberCount)
        AppEventBus.post(.terminalProcessTerminated(paneId: pane.id))

        await eventually("single-pane tab should close after AppEventBus delivery") {
            harness.store.tabs.isEmpty
        }
    }

    @Test("terminal process termination delivered through AppEventBus closes drawer children")
    func terminalProcessTermination_deliveredThroughAppEventBus_closesDrawerChild() async {
        let harness = makePaneTabControllerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let baselineSubscriberCount = await AppEventBus.shared.subscriberCount
        _ = harness.controller.view

        let parentPane = harness.store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/\(UUID().uuidString)")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Parent"), title: "Parent")
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        guard let drawerPane = harness.store.addDrawerPane(to: parentPane.id) else {
            Issue.record("Expected drawer pane creation to succeed")
            return
        }

        await waitForAppEventBusSubscriber(countGreaterThan: baselineSubscriberCount)
        AppEventBus.post(.terminalProcessTerminated(paneId: drawerPane.id))

        await eventually("drawer child should close after AppEventBus delivery") {
            harness.store.pane(drawerPane.id) == nil
        }
        #expect(harness.store.pane(parentPane.id) != nil)
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
