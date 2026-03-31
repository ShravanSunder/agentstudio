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

    private final class WeakControllerBox {
        weak var value: PaneTabViewController?

        init(_ value: PaneTabViewController?) {
            self.value = value
        }
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
        let appLifecycleStore = AppLifecycleStore()
        let windowLifecycleStore = WindowLifecycleStore()
        let applicationLifecycleMonitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appLifecycleStore,
            windowLifecycleStore: windowLifecycleStore
        )
        let controller = PaneTabViewController(
            store: store,
            repoCache: WorkspaceRepoCache(),
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
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

    private func waitForAppEventBusSubscriberCount(_ expectedCount: Int) async {
        for _ in 0..<1000 {
            if await AppEventBus.shared.subscriberCount >= expectedCount {
                return
            }
            await Task.yield()
        }
        Issue.record("Timed out waiting for AppEventBus subscriberCount >= \(expectedCount)")
    }

    private func stableAppEventBusSubscriberCount() async -> Int {
        var lastCount = await AppEventBus.shared.subscriberCount
        var stableObservations = 0

        for _ in 0..<1000 {
            await Task.yield()
            let currentCount = await AppEventBus.shared.subscriberCount
            if currentCount == lastCount {
                stableObservations += 1
                if stableObservations >= 10 {
                    return currentCount
                }
            } else {
                lastCount = currentCount
                stableObservations = 0
            }
        }

        return await AppEventBus.shared.subscriberCount
    }

    private func makeSubscribedPaneTabControllerHarness() async -> PaneTabControllerHarness {
        let baselineSubscriberCount = await stableAppEventBusSubscriberCount()
        let harness = makePaneTabControllerHarness()
        await waitForAppEventBusSubscriberCount(baselineSubscriberCount + 1)
        return harness
    }

    private func makeDroppedDeliverySubscriber() async -> AsyncStream<AppEvent> {
        await AppEventBus.shared.subscribe(bufferingPolicy: .bufferingNewest(0))
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

    @Test("process termination with subscribers suppresses a competing process-exited health update immediately")
    func processTermination_withSubscribers_immediatelySuppressesCompetingProcessExitedOverlay() async {
        let harness = await makeSubscribedPaneTabControllerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let mountView = makeProcessExitMountView()

        mountView.simulateSurfaceCloseForTesting(processAlive: false)
        mountView.applyHealthUpdateForTesting(.processExited(exitCode: nil))

        #expect(!mountView.isShowingErrorOverlayForTesting)
        #expect(mountView.isProcessExitedOverlaySuppressedAfterTerminationForTesting)

        await eventually("close event should be effectively delivered to a subscriber") {
            mountView.hasObservedEffectiveTerminationDeliveryForTesting
        }

        #expect(mountView.isProcessRunning == false)
        #expect(!mountView.isShowingErrorOverlayForTesting)
    }

    @Test("process termination with dropped delivery restores visible fallback UI")
    func processTermination_withDroppedDelivery_restoresFallbackOverlay() async {
        let baselineSubscriberCount = await stableAppEventBusSubscriberCount()
        var droppedDeliverySubscriber: AsyncStream<AppEvent>? = await makeDroppedDeliverySubscriber()
        #expect(droppedDeliverySubscriber != nil)
        await waitForAppEventBusSubscriberCount(baselineSubscriberCount + 1)
        let mountView = makeProcessExitMountView()

        mountView.simulateSurfaceCloseForTesting(processAlive: false)
        mountView.applyHealthUpdateForTesting(.processExited(exitCode: nil))

        #expect(!mountView.isShowingErrorOverlayForTesting)
        #expect(mountView.isProcessExitedOverlaySuppressedAfterTerminationForTesting)

        await eventually("fallback overlay should appear after dropped close delivery") {
            mountView.isShowingErrorOverlayForTesting
        }
        #expect(!mountView.hasObservedEffectiveTerminationDeliveryForTesting)

        droppedDeliverySubscriber = nil
        await waitForAppEventBusSubscriberCount(baselineSubscriberCount)
    }

    @Test("startup restore close with subscribers auto-closes without showing process-exit UI")
    func startupRestoreClose_withSubscribersAutoClosesWithoutProcessExitedUI() async {
        let harness = await makeSubscribedPaneTabControllerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let mountView = makeProcessExitMountView(showsRestorePresentationDuringStartup: true)

        mountView.beginRestorePresentationForTesting()
        #expect(mountView.isShowingStartupOverlayForTesting)

        mountView.simulateSurfaceCloseForTesting(processAlive: false)
        mountView.applyHealthUpdateForTesting(.processExited(exitCode: nil))

        #expect(!mountView.isShowingErrorOverlayForTesting)

        await eventually("startup close should be effectively delivered to a subscriber") {
            mountView.hasObservedEffectiveTerminationDeliveryForTesting
        }

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
        let baselineSubscriberCount = await stableAppEventBusSubscriberCount()
        let harness = makePaneTabControllerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let pane = harness.store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/\(UUID().uuidString)")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Solo"), title: "Solo")
        )
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)

        await waitForAppEventBusSubscriberCount(baselineSubscriberCount + 1)
        AppEventBus.post(.terminalProcessTerminated(paneId: pane.id))

        await eventually("single-pane tab should close after AppEventBus delivery") {
            harness.store.tabs.isEmpty
        }
    }

    @Test("terminal process termination delivered through AppEventBus closes drawer children")
    func terminalProcessTermination_deliveredThroughAppEventBus_closesDrawerChild() async {
        let baselineSubscriberCount = await stableAppEventBusSubscriberCount()
        let harness = makePaneTabControllerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
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

        await waitForAppEventBusSubscriberCount(baselineSubscriberCount + 1)
        AppEventBus.post(.terminalProcessTerminated(paneId: drawerPane.id))

        await eventually("drawer child should close after AppEventBus delivery") {
            harness.store.pane(drawerPane.id) == nil
        }
        #expect(harness.store.pane(parentPane.id) != nil)
    }

    @Test("terminal termination delivered through AppEventBus removes panes hidden from the active arrangement")
    func terminalProcessTermination_deliveredThroughAppEventBus_removesHiddenOwnedPane() async {
        let baselineSubscriberCount = await stableAppEventBusSubscriberCount()
        let harness = makePaneTabControllerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let paneA = harness.store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/a-\(UUID().uuidString)")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "A"), title: "A")
        )
        let paneB = harness.store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/b-\(UUID().uuidString)")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "B"), title: "B")
        )
        let hiddenPane = harness.store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/c-\(UUID().uuidString)")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Hidden"), title: "Hidden")
        )

        let tab = Tab(paneId: paneA.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(paneB.id, inTab: tab.id, at: paneA.id, direction: .horizontal, position: .after)
        harness.store.insertPane(hiddenPane.id, inTab: tab.id, at: paneB.id, direction: .horizontal, position: .after)
        guard
            let focusArrangementId = harness.store.createArrangement(
                name: "Focus",
                paneIds: Set([paneA.id, paneB.id]),
                inTab: tab.id
            )
        else {
            Issue.record("Expected focus arrangement creation to succeed")
            return
        }
        harness.store.switchArrangement(to: focusArrangementId, inTab: tab.id)
        #expect(harness.store.tab(tab.id)?.panes.contains(hiddenPane.id) == true)
        #expect(harness.store.tab(tab.id)?.paneIds.contains(hiddenPane.id) == false)

        await waitForAppEventBusSubscriberCount(baselineSubscriberCount + 1)
        AppEventBus.post(.terminalProcessTerminated(paneId: hiddenPane.id))

        await eventually("hidden owned pane should be removed without closing the whole tab") {
            harness.store.pane(hiddenPane.id) == nil
        }
        #expect(harness.store.tab(tab.id) != nil)
        #expect(harness.store.tab(tab.id)?.panes.contains(hiddenPane.id) == false)
        #expect(Set(harness.store.tab(tab.id)?.paneIds ?? []) == Set([paneA.id, paneB.id]))
    }

    @Test("requestClose immediately suppresses a competing process-exited health update")
    func requestClose_immediatelySuppressesCompetingProcessExitedOverlay() async {
        let harness = await makeSubscribedPaneTabControllerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let mountView = makeProcessExitMountView()

        mountView.requestClose()
        mountView.applyHealthUpdateForTesting(.processExited(exitCode: nil))

        #expect(mountView.isProcessRunning == false)
        #expect(!mountView.isShowingErrorOverlayForTesting)
        #expect(mountView.isProcessExitedOverlaySuppressedAfterTerminationForTesting)

        await eventually("requestClose should be effectively delivered to a subscriber") {
            mountView.hasObservedEffectiveTerminationDeliveryForTesting
        }
    }

    @Test("controller subscribes before view load and unregisters on teardown")
    func controller_subscribesBeforeViewLoad_andUnregistersOnTeardown() async {
        let baselineSubscriberCount = await stableAppEventBusSubscriberCount()
        var harness: PaneTabControllerHarness? = makePaneTabControllerHarness()
        let tempDir = harness?.tempDir
        let weakController = WeakControllerBox(harness?.controller)

        await waitForAppEventBusSubscriberCount(baselineSubscriberCount + 1)
        #expect(weakController.value != nil)

        harness = nil

        await eventually("controller should deallocate after teardown") {
            weakController.value == nil
        }
        await waitForAppEventBusSubscriberCount(baselineSubscriberCount)

        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
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
