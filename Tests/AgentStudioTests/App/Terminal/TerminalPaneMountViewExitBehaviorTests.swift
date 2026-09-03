import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioEditorChooser
@testable import AgentStudioInboxNotification
@testable import AgentStudioInfrastructure
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct TerminalPaneMountViewExitBehaviorTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }
    private struct PaneTabControllerHarness {
        let store: WorkspaceStore
        let controller: PaneTabViewController
        let appEventBus: EventBus<AppEvent>
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
        let store = WorkspaceStore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let surfaceManager = MockTerminalExitSurfaceManager()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: surfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )
        let executor = WorkspaceActionExecutor(coordinator: coordinator, store: store)
        let appLifecycleStore = AppLifecycleAtom()
        let windowLifecycleStore = WindowLifecycleAtom()
        let applicationLifecycleMonitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appLifecycleStore,
            windowLifecycleStore: windowLifecycleStore
        )
        let editorPreference = EditorPreferenceAtom()
        let editorChooserRuntime = EditorChooserRuntimeAtom()
        let editorChooser = EditorChooserState(
            preferenceAtom: editorPreference,
            runtimeAtom: editorChooserRuntime
        )
        let inboxAtom = InboxNotificationAtom()
        let appEventBus = EventBus<AppEvent>()
        let controller = PaneTabViewController(
            store: store,
            octiconLoader: makeTerminalTestOcticonLoader(),
            repoCache: RepoCacheAtom(),
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            executor: executor,
            runtimeCommandDispatcher: coordinator,
            tabBarAdapter: TabBarAdapter(
                store: store,
                repoCache: RepoCacheAtom(),
            ),
            viewRegistry: viewRegistry,
            bridgePaneAttendance: BridgePaneAttendanceAtom(),
            editorChooser: editorChooser,
            registersAsCommandHandler: false,
            appEventBus: appEventBus
        )
        return PaneTabControllerHarness(
            store: store,
            controller: controller,
            appEventBus: appEventBus,
            tempDir: tempDir
        )
    }

    private func waitForAppEventBusSubscriberCount(
        _ expectedCount: Int,
        on appEventBus: EventBus<AppEvent>
    ) async {
        for _ in 0..<1000 {
            if await appEventBus.subscriberCount == expectedCount {
                return
            }
            await Task.yield()
        }
        Issue.record("Timed out waiting for AppEventBus subscriberCount == \(expectedCount)")
    }

    private func makeSubscribedPaneTabControllerHarness() async -> PaneTabControllerHarness {
        let harness = makePaneTabControllerHarness()
        await waitForAppEventBusSubscriberCount(1, on: harness.appEventBus)
        return harness
    }

    private func waitForAppEventBusSubscriber(
        named subscriberName: String,
        on appEventBus: EventBus<AppEvent>,
        isPresent: Bool
    ) async {
        for _ in 0..<1000 {
            let activeSubscriberNames =
                await appEventBus
                .diagnosticsSnapshot()
                .activeSubscribers
                .map(\.subscriberName)
            if activeSubscriberNames.contains(subscriberName) == isPresent {
                return
            }
            await Task.yield()
        }
        Issue.record(
            "Timed out waiting for AppEventBus subscriber \(subscriberName) presence == \(isPresent)"
        )
    }

    private func makeProcessExitMountView(
        paneId: UUID = UUID(),
        showsRestorePresentationDuringStartup: Bool = false,
        appEventBus: EventBus<AppEvent> = EventBus<AppEvent>()
    ) -> TerminalPaneMountView {
        TerminalPaneMountView(
            restoredSurfaceId: UUID(),
            paneId: paneId,
            title: "Terminal",
            showsRestorePresentationDuringStartup: showsRestorePresentationDuringStartup,
            appEventBus: appEventBus
        )
    }

    private func makeSubscribedPaneId(in store: WorkspaceStore) -> UUID {
        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/\(UUID().uuidString)")!)),
            metadata: PaneMetadata(title: "Terminal")
        )
        store.appendTab(Tab(paneId: pane.id))
        return pane.id
    }

    @Test("process termination without subscribers keeps a visible fallback")
    func processTermination_withoutSubscribers_showsFallbackOverlay() async {
        let mountView = makeProcessExitMountView()

        let terminationTask = mountView.simulateSurfaceCloseForTesting(processAlive: false)
        #expect(mountView.isProcessRunning == false)

        await terminationTask?.value
        mountView.applyHealthUpdateForTesting(.processExited(exitCode: nil))

        #expect(mountView.isShowingErrorOverlayForTesting)
    }

    @Test("process termination with subscribers suppresses a competing process-exited health update immediately")
    func processTermination_withSubscribers_immediatelySuppressesCompetingProcessExitedOverlay() async {
        let harness = await makeSubscribedPaneTabControllerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let paneId = makeSubscribedPaneId(in: harness.store)

        let mountView = makeProcessExitMountView(paneId: paneId, appEventBus: harness.appEventBus)

        let terminationTask = mountView.simulateSurfaceCloseForTesting(processAlive: false)
        mountView.applyHealthUpdateForTesting(.processExited(exitCode: nil))

        #expect(!mountView.isShowingErrorOverlayForTesting)
        #expect(mountView.isProcessExitedOverlaySuppressedAfterTerminationForTesting)

        await terminationTask?.value
        #expect(mountView.isProcessRunning == false)
        #expect(!mountView.isShowingErrorOverlayForTesting)
    }

    @Test("process termination ignored by a subscribed controller restores visible fallback UI")
    func processTermination_ignoredBySubscribedController_restoresFallbackOverlay() async {
        let harness = await makeSubscribedPaneTabControllerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let mountView = makeProcessExitMountView(
            paneId: UUIDv7.generate(),
            appEventBus: harness.appEventBus
        )

        let terminationTask = mountView.simulateSurfaceCloseForTesting(processAlive: false)
        mountView.applyHealthUpdateForTesting(.processExited(exitCode: nil))

        #expect(!mountView.isShowingErrorOverlayForTesting)
        await terminationTask?.value
        #expect(mountView.isShowingErrorOverlayForTesting)
        #expect(!mountView.hasObservedEffectiveTerminationDeliveryForTesting)
    }

    @Test("process termination with dropped delivery restores visible fallback UI")
    func processTermination_withDroppedDelivery_restoresFallbackOverlay() async {
        let subscriberName = "TerminalPaneMountViewExitBehaviorTests.droppedDelivery"
        let appEventBus = EventBus<AppEvent>()
        var droppedDeliverySubscriber: EventBusSubscription<AppEvent>? = await appEventBus.subscribe(
            policy: .lossyNewest(0),
            subscriberName: subscriberName
        )
        #expect(droppedDeliverySubscriber != nil)
        await waitForAppEventBusSubscriber(named: subscriberName, on: appEventBus, isPresent: true)
        let mountView = makeProcessExitMountView(appEventBus: appEventBus)

        let terminationTask = mountView.simulateSurfaceCloseForTesting(processAlive: false)
        mountView.applyHealthUpdateForTesting(.processExited(exitCode: nil))

        #expect(!mountView.isShowingErrorOverlayForTesting)
        #expect(mountView.isProcessExitedOverlaySuppressedAfterTerminationForTesting)

        await terminationTask?.value
        #expect(mountView.isShowingErrorOverlayForTesting)
        #expect(!mountView.hasObservedEffectiveTerminationDeliveryForTesting)

        droppedDeliverySubscriber = nil
        await waitForAppEventBusSubscriber(named: subscriberName, on: appEventBus, isPresent: false)
    }

    @Test("startup restore close with subscribers auto-closes without showing process-exit UI")
    func startupRestoreClose_withSubscribersAutoClosesWithoutProcessExitedUI() async {
        let harness = await makeSubscribedPaneTabControllerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let paneId = makeSubscribedPaneId(in: harness.store)

        let mountView = makeProcessExitMountView(
            paneId: paneId,
            showsRestorePresentationDuringStartup: true,
            appEventBus: harness.appEventBus
        )

        mountView.beginRestorePresentationForTesting()
        #expect(mountView.isShowingStartupOverlayForTesting)

        let terminationTask = mountView.simulateSurfaceCloseForTesting(processAlive: false)
        mountView.applyHealthUpdateForTesting(.processExited(exitCode: nil))

        #expect(!mountView.isShowingErrorOverlayForTesting)

        await terminationTask?.value
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
        let pane = harness.store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/\(UUID().uuidString)")!)),
            metadata: PaneMetadata(title: "Solo")
        )
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)

        await waitForAppEventBusSubscriberCount(1, on: harness.appEventBus)
        await harness.appEventBus.post(.terminalProcessTerminated(paneId: pane.id))

        await eventually("single-pane tab should close after AppEventBus delivery") {
            harness.store.tabs.isEmpty
        }
    }

    @Test("terminal process termination delivered through AppEventBus closes drawer children")
    func terminalProcessTermination_deliveredThroughAppEventBus_closesDrawerChild() async {
        let harness = makePaneTabControllerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let parentPane = harness.store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/\(UUID().uuidString)")!)),
            metadata: PaneMetadata(title: "Parent")
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        guard
            let drawerPane = harness.store.addDrawerPane(
                to: parentPane.id,
                parentFallbackCWD: FileManager.default.homeDirectoryForCurrentUser
            )
        else {
            Issue.record("Expected drawer pane creation to succeed")
            return
        }

        await waitForAppEventBusSubscriberCount(1, on: harness.appEventBus)
        await harness.appEventBus.post(.terminalProcessTerminated(paneId: drawerPane.id))

        await eventually("drawer child should close after AppEventBus delivery") {
            harness.store.pane(drawerPane.id) == nil
        }
        #expect(harness.store.pane(parentPane.id) != nil)
    }

    @Test("terminal termination delivered through AppEventBus removes minimized panes from the active arrangement")
    func terminalProcessTermination_deliveredThroughAppEventBus_removesMinimizedOwnedPane() async {
        let harness = makePaneTabControllerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let paneA = harness.store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/a-\(UUID().uuidString)")!)),
            metadata: PaneMetadata(title: "A")
        )
        let paneB = harness.store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/b-\(UUID().uuidString)")!)),
            metadata: PaneMetadata(title: "B")
        )
        let minimizedPane = harness.store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/c-\(UUID().uuidString)")!)),
            metadata: PaneMetadata(title: "Minimized")
        )

        let tab = Tab(paneId: paneA.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            paneB.id, inTab: tab.id, at: paneA.id, direction: .horizontal, position: .after, sizingMode: .halveTarget)
        harness.store.insertPane(
            minimizedPane.id, inTab: tab.id, at: paneB.id, direction: .horizontal, position: .after,
            sizingMode: .halveTarget)
        guard harness.store.minimizePane(minimizedPane.id, inTab: tab.id) else {
            Issue.record("Expected pane minimization to succeed")
            return
        }
        #expect(harness.store.tab(tab.id)?.panes.contains(minimizedPane.id) == true)
        #expect(harness.store.tab(tab.id)?.activeMinimizedPaneIds.contains(minimizedPane.id) == true)

        await waitForAppEventBusSubscriberCount(1, on: harness.appEventBus)
        await harness.appEventBus.post(.terminalProcessTerminated(paneId: minimizedPane.id))

        await eventually("minimized owned pane should be removed without closing the whole tab") {
            harness.store.pane(minimizedPane.id) == nil
        }
        #expect(harness.store.tab(tab.id) != nil)
        #expect(harness.store.tab(tab.id)?.panes.contains(minimizedPane.id) == false)
        #expect(Set(harness.store.tab(tab.id)?.paneIds ?? []) == Set([paneA.id, paneB.id]))
    }

    @Test("requestClose immediately suppresses a competing process-exited health update")
    func requestClose_immediatelySuppressesCompetingProcessExitedOverlay() async {
        let harness = await makeSubscribedPaneTabControllerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let paneId = makeSubscribedPaneId(in: harness.store)

        let mountView = makeProcessExitMountView(paneId: paneId, appEventBus: harness.appEventBus)

        let terminationTask = mountView.requestClose()
        mountView.applyHealthUpdateForTesting(.processExited(exitCode: nil))

        #expect(mountView.isProcessRunning == false)
        #expect(!mountView.isShowingErrorOverlayForTesting)
        #expect(mountView.isProcessExitedOverlaySuppressedAfterTerminationForTesting)

        await terminationTask?.value
        #expect(mountView.hasObservedEffectiveTerminationDeliveryForTesting)
    }

    @Test("restart delegates repair exactly once without removing or destroying the current surface")
    func restartDelegatesRepairWithoutPredestroyingSurface() throws {
        let surfaceID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let mountView = TerminalPaneMountView(
            restoredSurfaceId: surfaceID,
            paneId: paneID,
            title: "Terminal"
        )
        var repairRequests: [UUID] = []
        mountView.onRepairRequested = { repairRequests.append($0) }
        mountView.applyHealthUpdateForTesting(.dead)
        let overlay = try #require(mountView.errorOverlay)

        overlay.onRestart?()

        #expect(repairRequests == [paneID])
        #expect(mountView.surfaceId == surfaceID)
    }

    @Test("controller subscribes before view load and unregisters on teardown")
    func controller_subscribesBeforeViewLoad_andUnregistersOnTeardown() async {
        var harness: PaneTabControllerHarness? = makePaneTabControllerHarness()
        let tempDir = harness?.tempDir
        let weakController = WeakControllerBox(harness?.controller)

        let appEventBus = harness?.appEventBus
        if let appEventBus {
            await waitForAppEventBusSubscriberCount(1, on: appEventBus)
        }
        #expect(weakController.value != nil)

        harness = nil

        await eventually("controller should deallocate after teardown") {
            weakController.value == nil
        }
        if let appEventBus {
            await waitForAppEventBusSubscriberCount(0, on: appEventBus)
        }

        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }
}

@MainActor
private final class MockTerminalExitSurfaceManager: WorkspaceSurfaceManaging {
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
