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
    @MainActor
    private struct PaneTabControllerHarness {
        let store: WorkspaceStore
        let controller: PaneTabViewController
        let coordinator: WorkspaceSurfaceCoordinator
        let executor: WorkspaceActionExecutor
        let appEventBus: EventBus<AppEvent>
        let tempDir: URL

        func shutdown() async {
            controller.shutdown()
            await executor.stopAcceptingCommandsAndDrain()
            await coordinator.shutdown()
        }
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
        let store: WorkspaceStore
        do {
            store = try makeWorkspaceJournalTestStore()
        } catch {
            preconditionFailure("Could not prepare the terminal-exit journal fixture: \(error)")
        }
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
            heldPanePreviewState: HeldPanePreviewState(),
            registersAsCommandHandler: false,
            appEventBus: appEventBus
        )
        return PaneTabControllerHarness(
            store: store,
            controller: controller,
            coordinator: coordinator,
            executor: executor,
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
        appEventBus: EventBus<AppEvent> = EventBus<AppEvent>(),
        terminationAcknowledgementClock: TestPushClock? = nil
    ) -> TerminalPaneMountView {
        TerminalPaneMountView(
            restoredSurfaceId: UUID(),
            paneId: paneId,
            title: "Terminal",
            showsRestorePresentationDuringStartup: showsRestorePresentationDuringStartup,
            appEventBus: appEventBus,
            terminationAcknowledgementClock: terminationAcknowledgementClock
        )
    }

    private func events(
        through sentinelPaneId: UUID,
        from stream: EventBusSubscription<AppEvent>
    ) async -> [AppEvent] {
        var receivedEvents: [AppEvent] = []
        for await event in stream {
            receivedEvents.append(event)
            if case .worktreeBellRang(let paneId) = event, paneId == sentinelPaneId {
                return receivedEvents
            }
        }
        return receivedEvents
    }

    private func simulateGhosttyCloseCallback(
        processExited: Bool,
        on mountView: TerminalPaneMountView
    ) {
        mountView.simulateSurfaceCloseForTesting(processExited: processExited)
    }

    private func makeSubscribedPaneId(in store: WorkspaceStore) -> UUID {
        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/\(UUID().uuidString)")!)),
            metadata: PaneMetadata(title: "Terminal")
        )
        store.appendTab(Tab(paneId: pane.id))
        return pane.id
    }

    @Test("Ghostty close callback while running does not dispatch pane close")
    func ghosttyCloseCallbackWhileRunning_doesNotClosePane() async {
        let store = WorkspaceStore()
        let paneId = makeSubscribedPaneId(in: store)
        let tabId = store.tabs[0].id
        let appEventBus = EventBus<AppEvent>()
        let eventRecorder = await appEventBus.subscribe(
            policy: .criticalUnbounded,
            subscriberName: "TerminalPaneMountViewExitBehaviorTests.liveCloseRecorder"
        )
        let mountView = makeProcessExitMountView(
            paneId: paneId,
            appEventBus: appEventBus
        )

        simulateGhosttyCloseCallback(processExited: false, on: mountView)

        let sentinelPaneId = UUIDv7.generate()
        await appEventBus.post(.worktreeBellRang(paneId: sentinelPaneId))
        let receivedEvents = await events(through: sentinelPaneId, from: eventRecorder)

        #expect(
            !receivedEvents.contains { event in
                if case .terminalProcessTerminated = event { return true }
                return false
            })
        #expect(store.tabLayoutAtom.tab(tabId) != nil)
        #expect(store.paneAtom.pane(paneId) != nil)
        #expect(mountView.isProcessRunning)
        #expect(!mountView.isShowingErrorOverlayForTesting)

    }

    @Test("Ghostty close callback after exit keeps pane and shows Process Exited")
    func ghosttyCloseCallbackAfterExit_keepsPaneAndShowsOverlay() async {
        let store = WorkspaceStore()
        let paneId = makeSubscribedPaneId(in: store)
        let tabId = store.tabs[0].id
        let appEventBus = EventBus<AppEvent>()
        let eventRecorder = await appEventBus.subscribe(
            policy: .criticalUnbounded,
            subscriberName: "TerminalPaneMountViewExitBehaviorTests.exitedCloseRecorder"
        )
        let mountView = makeProcessExitMountView(
            paneId: paneId,
            appEventBus: appEventBus
        )

        simulateGhosttyCloseCallback(processExited: true, on: mountView)

        let sentinelPaneId = UUIDv7.generate()
        await appEventBus.post(.worktreeBellRang(paneId: sentinelPaneId))
        let receivedEvents = await events(through: sentinelPaneId, from: eventRecorder)

        #expect(
            !receivedEvents.contains { event in
                if case .terminalProcessTerminated = event { return true }
                return false
            })
        #expect(store.tabLayoutAtom.tab(tabId) != nil)
        #expect(store.paneAtom.pane(paneId) != nil)
        #expect(!mountView.isProcessRunning)
        #expect(mountView.isShowingErrorOverlayForTesting)

    }

    @Test("Ghostty process exit callback keeps the Process Exited fallback without subscribers")
    func ghosttyProcessExit_withoutSubscribers_showsFallbackOverlay() {
        let mountView = makeProcessExitMountView()

        mountView.simulateSurfaceCloseForTesting(processExited: true)
        #expect(mountView.isProcessRunning == false)
        #expect(mountView.isShowingErrorOverlayForTesting)
    }

    @Test("Ghostty process exit callback with subscribers keeps the pane and Process Exited overlay")
    func ghosttyProcessExit_withSubscribersKeepsPaneAndOverlay() async {
        let harness = await makeSubscribedPaneTabControllerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let paneId = makeSubscribedPaneId(in: harness.store)

        let mountView = makeProcessExitMountView(paneId: paneId, appEventBus: harness.appEventBus)

        mountView.simulateSurfaceCloseForTesting(processExited: true)
        mountView.applyHealthUpdateForTesting(.processExited(exitCode: nil))

        #expect(mountView.isShowingErrorOverlayForTesting)
        #expect(!mountView.isProcessExitedOverlaySuppressedAfterTerminationForTesting)
        #expect(harness.store.paneAtom.pane(paneId) != nil)

        #expect(mountView.isProcessRunning == false)
        await harness.shutdown()
    }

    @Test("Ghostty close request for a running process is ignored with a subscribed controller")
    func ghosttyCloseRequest_whileRunningIsIgnoredWithSubscribedController() async {
        let harness = await makeSubscribedPaneTabControllerHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let paneId = makeSubscribedPaneId(in: harness.store)
        let mountView = makeProcessExitMountView(paneId: paneId, appEventBus: harness.appEventBus)

        mountView.simulateSurfaceCloseForTesting(processExited: false)

        #expect(mountView.isProcessRunning)
        #expect(!mountView.isShowingErrorOverlayForTesting)
        #expect(harness.store.paneAtom.pane(paneId) != nil)
        await harness.shutdown()
    }

    @Test("app-owned close with dropped delivery restores visible fallback UI")
    func appOwnedClose_withDroppedDeliveryRestoresFallbackOverlay() async {
        let clock = TestPushClock()
        let subscriberName = "TerminalPaneMountViewExitBehaviorTests.droppedDelivery"
        let appEventBus = EventBus<AppEvent>()
        var droppedDeliverySubscriber: EventBusSubscription<AppEvent>? = await appEventBus.subscribe(
            policy: .lossyNewest(0),
            subscriberName: subscriberName
        )
        #expect(droppedDeliverySubscriber != nil)
        await waitForAppEventBusSubscriber(named: subscriberName, on: appEventBus, isPresent: true)
        let mountView = makeProcessExitMountView(appEventBus: appEventBus, terminationAcknowledgementClock: clock)

        let terminationTask = mountView.requestClose()
        mountView.applyHealthUpdateForTesting(.processExited(exitCode: nil))

        #expect(!mountView.isShowingErrorOverlayForTesting)
        #expect(mountView.isProcessExitedOverlaySuppressedAfterTerminationForTesting)

        await clock.waitForPendingSleepCount(atLeast: 1)
        clock.advance(by: AppPolicies.TerminalProcessTermination.acknowledgementTimeout)
        await terminationTask?.value
        #expect(mountView.isShowingErrorOverlayForTesting)
        #expect(!mountView.hasObservedEffectiveTerminationDeliveryForTesting)

        droppedDeliverySubscriber = nil
        await waitForAppEventBusSubscriber(named: subscriberName, on: appEventBus, isPresent: false)
    }

    @Test("startup restore process exit keeps its pane and shows Process Exited")
    func startupRestoreGhosttyExit_keepsPaneAndShowsProcessExitedUI() async {
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

        mountView.simulateSurfaceCloseForTesting(processExited: true)
        mountView.applyHealthUpdateForTesting(.processExited(exitCode: nil))

        #expect(mountView.isShowingErrorOverlayForTesting)
        #expect(mountView.isProcessRunning == false)
        #expect(!mountView.isShowingStartupOverlayForTesting)
        #expect(harness.store.paneAtom.pane(paneId) != nil)
        await harness.shutdown()
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
        await harness.shutdown()
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
            await harness.shutdown()
            return
        }

        await waitForAppEventBusSubscriberCount(1, on: harness.appEventBus)
        await harness.appEventBus.post(.terminalProcessTerminated(paneId: drawerPane.id))

        await eventually("drawer child should close after AppEventBus delivery") {
            harness.store.pane(drawerPane.id) == nil
        }
        #expect(harness.store.pane(parentPane.id) != nil)
        await harness.shutdown()
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
            await harness.shutdown()
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
        await harness.shutdown()
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
        await harness.shutdown()
    }

    @Test("termination waits for its matching acknowledgment and drains the timeout")
    func terminationWaitsForMatchingAcknowledgment() async {
        let clock = TestPushClock()
        let appEventBus = EventBus<AppEvent>()
        let terminationConsumer = await appEventBus.subscribe(
            policy: .criticalUnbounded,
            subscriberName: "TerminalPaneMountViewExitBehaviorTests.terminationConsumer"
        )
        var terminationEvents = terminationConsumer.makeAsyncIterator()
        let mountView = makeProcessExitMountView(
            appEventBus: appEventBus,
            terminationAcknowledgementClock: clock
        )
        let terminationTask = mountView.requestClose()
        _ = await terminationEvents.next()
        await clock.waitForPendingSleepCount(atLeast: 1)
        #expect(mountView.isProcessExitedOverlaySuppressedAfterTerminationForTesting)
        #expect(!mountView.hasObservedEffectiveTerminationDeliveryForTesting)

        await appEventBus.post(.terminalProcessTerminationHandled(paneId: UUIDv7.generate()))
        await appEventBus.post(.terminalProcessTerminationHandled(paneId: mountView.paneId))
        await terminationTask?.value

        #expect(mountView.hasObservedEffectiveTerminationDeliveryForTesting)
        #expect(!mountView.isShowingErrorOverlayForTesting)
        #expect(clock.pendingSleepCount == 0)
        await waitForAppEventBusSubscriber(
            named: "TerminalPaneMountView.terminationAcknowledgement",
            on: appEventBus,
            isPresent: false
        )
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
    func retainSurfacesForUndo(forPaneIDs paneIDs: Set<UUID>) {}
    func retireActiveAndHiddenSurfaces(forPaneIDs paneIDs: Set<UUID>) {}

    func releaseUndoSurfaces(forPaneIDs paneIDs: Set<UUID>) {}

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

    func undoClose(forPaneId paneId: UUID) -> ManagedSurface? { nil }

    func destroy(_ surfaceId: UUID) {
        _ = surfaceId
    }
}
