import AppKit
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerTabRetentionTests {
    private struct Harness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let controller: PaneTabViewController
        let window: NSWindow
        let tempDir: URL
    }

    private func makeHarness() -> Harness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-tab-retention-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let appLifecycleStore = AppLifecycleStore()
        let windowLifecycleStore = WindowLifecycleStore()
        let applicationLifecycleMonitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appLifecycleStore,
            windowLifecycleStore: windowLifecycleStore
        )
        let coordinator = makeTestPaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: MockPersistentTabSurfaceManager(),
            runtimeRegistry: RuntimeRegistry()
        )
        let controller = PaneTabViewController(
            store: store,
            repoCache: WorkspaceRepoCache(),
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            executor: ActionExecutor(coordinator: coordinator, store: store),
            tabBarAdapter: TabBarAdapter(store: store, repoCache: WorkspaceRepoCache()),
            viewRegistry: viewRegistry
        )
        PaneViewRepresentable.onDismantleForTesting = { [weak controller] in
            controller?.recordPaneRepresentableDismantleForTesting()
        }
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
            controller: controller,
            window: window,
            tempDir: tempDir
        )
    }

    private func registerPaneHost(_ paneId: UUID, in harness: Harness) {
        harness.viewRegistry.register(PaneHostView(paneId: paneId), for: paneId)
    }

    @Test
    func switchingTabs_reusesPersistentHosts() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let firstPane = harness.store.createPane(
            source: .floating(workingDirectory: harness.tempDir, title: "First"),
            provider: .zmx
        )
        let secondPane = harness.store.createPane(
            source: .floating(workingDirectory: harness.tempDir, title: "Second"),
            provider: .zmx
        )
        let firstTab = Tab(paneId: firstPane.id, name: "First")
        let secondTab = Tab(paneId: secondPane.id, name: "Second")
        harness.store.appendTab(firstTab)
        harness.store.appendTab(secondTab)
        registerPaneHost(firstPane.id, in: harness)
        registerPaneHost(secondPane.id, in: harness)
        harness.store.setActiveTab(firstTab.id)
        harness.controller.view.layoutSubtreeIfNeeded()

        let firstHost = try #require(harness.controller.tabHostViewForTesting(tabId: firstTab.id))

        harness.store.setActiveTab(secondTab.id)
        harness.controller.view.layoutSubtreeIfNeeded()
        let secondHost = try #require(harness.controller.tabHostViewForTesting(tabId: secondTab.id))

        harness.store.setActiveTab(firstTab.id)
        harness.controller.view.layoutSubtreeIfNeeded()
        let firstHostAfterRoundTrip = try #require(
            harness.controller.tabHostViewForTesting(tabId: firstTab.id)
        )

        #expect(firstHostAfterRoundTrip === firstHost)
        #expect(secondHost !== firstHost)
    }

    @Test
    func activeTabChanges_doNotDismantleStillExistingTabHosts() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let firstPane = harness.store.createPane(
            source: .floating(workingDirectory: harness.tempDir, title: "First"),
            provider: .zmx
        )
        let secondPane = harness.store.createPane(
            source: .floating(workingDirectory: harness.tempDir, title: "Second"),
            provider: .zmx
        )
        let firstTab = Tab(paneId: firstPane.id, name: "First")
        let secondTab = Tab(paneId: secondPane.id, name: "Second")
        harness.store.appendTab(firstTab)
        harness.store.appendTab(secondTab)
        registerPaneHost(firstPane.id, in: harness)
        registerPaneHost(secondPane.id, in: harness)
        harness.store.setActiveTab(firstTab.id)
        harness.controller.view.layoutSubtreeIfNeeded()

        let dismantleCountBeforeSwitch = harness.controller.paneRepresentableDismantleCountForTesting

        harness.store.setActiveTab(secondTab.id)
        harness.controller.view.layoutSubtreeIfNeeded()

        #expect(
            harness.controller.paneRepresentableDismantleCountForTesting == dismantleCountBeforeSwitch
        )
    }

    @Test
    func withinTabStateChanges_doNotDismantleRepresentables() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(
            source: .floating(workingDirectory: harness.tempDir, title: "Focused"),
            provider: .zmx
        )
        let tab = Tab(paneId: pane.id, name: "Focused")
        harness.store.appendTab(tab)
        registerPaneHost(pane.id, in: harness)
        harness.store.setActiveTab(tab.id)
        harness.controller.view.layoutSubtreeIfNeeded()

        let dismantleCountBeforeMutation = harness.controller.paneRepresentableDismantleCountForTesting

        harness.store.bumpViewRevision()
        harness.controller.view.layoutSubtreeIfNeeded()

        #expect(
            harness.controller.paneRepresentableDismantleCountForTesting == dismantleCountBeforeMutation
        )
    }
}

@MainActor
private final class MockPersistentTabSurfaceManager: PaneCoordinatorSurfaceManaging {
    private let cwdStream = AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { continuation in
        continuation.finish()
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { cwdStream }

    func syncFocus(activeSurfaceId _: UUID?) {}

    func createSurface(
        config _: Ghostty.SurfaceConfiguration,
        metadata _: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> { .failure(.operationFailed("test")) }

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
