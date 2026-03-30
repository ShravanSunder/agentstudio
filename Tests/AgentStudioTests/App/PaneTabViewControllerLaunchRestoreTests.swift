import AppKit
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerLaunchRestoreTests {
    private struct Harness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let runtime: SessionRuntime
        let coordinator: PaneCoordinator
        let executor: ActionExecutor
        let appLifecycleStore: AppLifecycleStore
        let windowLifecycleStore: WindowLifecycleStore
        let applicationLifecycleMonitor: ApplicationLifecycleMonitor
        let controller: PaneTabViewController
        let surfaceManager: LaunchCapturingSurfaceManager
        let window: NSWindow
        let tempDir: URL
    }

    private func makeHarness() -> Harness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-tab-launch-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore(persistor: persistor)
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let appLifecycleStore = AppLifecycleStore()
        let windowLifecycleStore = WindowLifecycleStore()
        let applicationLifecycleMonitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appLifecycleStore,
            windowLifecycleStore: windowLifecycleStore
        )
        let surfaceManager = LaunchCapturingSurfaceManager()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: surfaceManager,
            runtimeRegistry: .shared,
            windowLifecycleStore: windowLifecycleStore
        )
        let executor = ActionExecutor(coordinator: coordinator, store: store)
        let controller = PaneTabViewController(
            store: store,
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            executor: executor,
            tabBarAdapter: TabBarAdapter(store: store),
            viewRegistry: viewRegistry
        )
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 1200, height: 800),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()

        return Harness(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            coordinator: coordinator,
            executor: executor,
            appLifecycleStore: appLifecycleStore,
            windowLifecycleStore: windowLifecycleStore,
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            controller: controller,
            surfaceManager: surfaceManager,
            window: window,
            tempDir: tempDir
        )
    }

    @Test
    func layout_writesNonEmptyBoundsToWindowLifecycleStore() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        harness.controller.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        harness.controller.view.layoutSubtreeIfNeeded()

        #expect(harness.windowLifecycleStore.terminalContainerBounds.width > 0)
        #expect(harness.windowLifecycleStore.terminalContainerBounds.height > 0)
        #expect(harness.windowLifecycleStore.isReadyForLaunchRestore == false)
    }

    @Test
    func settledLayoutWithRecordedBounds_makesStoreReadyForLaunchRestore() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        harness.controller.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        harness.controller.view.layoutSubtreeIfNeeded()
        harness.applicationLifecycleMonitor.handleLaunchLayoutSettled()

        #expect(harness.windowLifecycleStore.isLaunchLayoutSettled == true)
        #expect(harness.windowLifecycleStore.isReadyForLaunchRestore == true)
    }

    @Test
    func restoreViewsForActiveTabIfNeeded_doesNotCreateViewsBeforeLaunchLayoutSettles() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(
            source: .floating(workingDirectory: harness.tempDir, title: "Early Restore"),
            provider: .zmx
        )
        let tab = Tab(paneId: pane.id, name: "Early Restore")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        harness.windowLifecycleStore.recordTerminalContainerBounds(
            CGRect(x: 0, y: 0, width: 512, height: 552)
        )
        #expect(harness.windowLifecycleStore.isReadyForLaunchRestore == false)

        harness.coordinator.restoreViewsForActiveTabIfNeeded()

        #expect(harness.surfaceManager.createdPaneIds.isEmpty)
    }

    @Test
    func restoreAllViews_usesLifecycleStoreBounds() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(
            source: .floating(workingDirectory: harness.tempDir, title: "Launch Restore"),
            provider: .zmx
        )
        let tab = Tab(paneId: pane.id, name: "Launch Restore")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        let containerWidth: CGFloat = 1000
        let containerHeight: CGFloat = 600
        harness.windowLifecycleStore.recordTerminalContainerBounds(
            CGRect(x: 0, y: 0, width: containerWidth, height: containerHeight)
        )

        await harness.coordinator.restoreAllViews(
            in: harness.windowLifecycleStore.terminalContainerBounds
        )

        let config = try #require(harness.surfaceManager.createdConfigsByPaneId[pane.id])
        let gap = AppStyle.paneGap
        #expect(
            config.initialFrame
                == CGRect(x: gap, y: gap, width: containerWidth - gap * 2, height: containerHeight - gap * 2))
    }

    @Test
    func appLifecycleChanges_doNotReplaceSplitHostingView() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let originalSplitHostingView = try #require(harness.controller.splitHostingViewForTesting)
        #expect(harness.controller.appLifecycleStoreForTesting === harness.appLifecycleStore)

        harness.applicationLifecycleMonitor.handleApplicationDidBecomeActive()
        harness.controller.view.layoutSubtreeIfNeeded()

        let updatedSplitHostingView = try #require(harness.controller.splitHostingViewForTesting)
        #expect(updatedSplitHostingView === originalSplitHostingView)

        harness.applicationLifecycleMonitor.handleApplicationDidResignActive()
        harness.controller.view.layoutSubtreeIfNeeded()

        let splitHostingViewAfterResign = try #require(harness.controller.splitHostingViewForTesting)
        #expect(splitHostingViewAfterResign === originalSplitHostingView)
    }
}

@MainActor
private final class LaunchCapturingSurfaceManager: PaneCoordinatorSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>

    private(set) var createdPaneIds: [UUID] = []
    private(set) var createdConfigsByPaneId: [UUID: Ghostty.SurfaceConfiguration] = [:]

    init() {
        self.cwdStream = AsyncStream { continuation in
            continuation.onTermination = { _ in }
        }
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { cwdStream }

    func syncFocus(activeSurfaceId _: UUID?) {}

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        if let paneId = metadata.paneId {
            createdPaneIds.append(paneId)
            createdConfigsByPaneId[paneId] = config
        }
        return .failure(.operationFailed("capture only"))
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        _ = surfaceId
        _ = paneId
        return nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {
        _ = surfaceId
        _ = reason
    }

    func undoClose() -> ManagedSurface? { nil }

    func requeueUndo(_ surfaceId: UUID) {
        _ = surfaceId
    }

    func destroy(_ surfaceId: UUID) {
        _ = surfaceId
    }
}
