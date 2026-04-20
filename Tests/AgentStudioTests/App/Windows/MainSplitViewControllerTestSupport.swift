import AppKit
import Foundation
import GhosttyKit
import SwiftUI

@testable import AgentStudio

@MainActor
struct MainSplitViewControllerHarness {
    let atoms: AtomRegistry
    let store: WorkspaceStore
    let coordinator: PaneCoordinator
    let controller: MainSplitViewController
    let window: NSWindow
    let tempDir: URL
}

@MainActor
func withMainSplitViewControllerHarness<T>(
    withRepos: Bool = true,
    configureUIState: @MainActor (UIStateAtom) -> Void = { _ in },
    body: @MainActor (MainSplitViewControllerHarness) async throws -> T
) async rethrows -> T {
    let tempDir = FileManager.default.temporaryDirectory
        .appending(path: "main-split-view-controller-tests-\(UUID().uuidString)")
    let persistor = WorkspacePersistor(workspacesDir: tempDir)
    let atoms = AtomRegistry()
    configureUIState(atoms.uiState)

    let store = WorkspaceStore(
        metadataAtom: atoms.workspaceMetadata,
        repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
        paneAtom: atoms.workspacePane,
        tabLayoutAtom: atoms.workspaceTabLayout,
        mutationCoordinator: atoms.workspaceMutationCoordinator,
        persistor: persistor
    )
    store.restore()

    if withRepos {
        _ = store.addRepo(at: tempDir.appending(path: "repo"))
    }

    let viewRegistry = ViewRegistry()
    let runtime = SessionRuntime(atom: atoms.sessionRuntime, store: store)
    let coordinator = PaneCoordinator(
        store: store,
        viewRegistry: viewRegistry,
        runtime: runtime,
        surfaceManager: MainSplitViewControllerTestSurfaceManager(),
        runtimeRegistry: RuntimeRegistry(),
        windowLifecycleStore: WindowLifecycleAtom()
    )
    let actionExecutor = ActionExecutor(coordinator: coordinator, store: store)
    let appLifecycleStore = AppLifecycleAtom()
    let applicationLifecycleMonitor = ApplicationLifecycleMonitor(
        appLifecycleStore: appLifecycleStore,
        windowLifecycleStore: WindowLifecycleAtom()
    )
    let tabBarAdapter = TabBarAdapter(store: store, repoCache: atoms.repoCache)
    let controller = MainSplitViewController(
        store: store,
        actionExecutor: actionExecutor,
        applicationLifecycleMonitor: applicationLifecycleMonitor,
        appLifecycleStore: appLifecycleStore,
        tabBarAdapter: tabBarAdapter,
        viewRegistry: viewRegistry,
        sidebarRootViewBuilder: { _, uiState, _ in
            AnyView(MainSplitViewControllerTestSidebarView(uiState: uiState))
        }
    )
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )

    let harness = MainSplitViewControllerHarness(
        atoms: atoms,
        store: store,
        coordinator: coordinator,
        controller: controller,
        window: window,
        tempDir: tempDir
    )

    let result = try await AtomScope.$override.withValue(atoms) {
        window.contentViewController = controller
        _ = controller.view
        window.makeKeyAndOrderFront(nil)
        return try await body(harness)
    }

    controller.shutdown()
    window.contentViewController = nil
    window.orderOut(nil)
    await Task.yield()
    await coordinator.shutdown()
    try? FileManager.default.removeItem(at: tempDir)
    return result
}

private struct MainSplitViewControllerTestSidebarView: View {
    let uiState: UIStateAtom

    var body: some View {
        Group {
            switch uiState.sidebarSurface {
            case .repos:
                Color.clear
            case .inbox:
                InboxNotificationPlaceholderView(uiState: uiState)
            }
        }
        .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
    }
}

private final class MainSplitViewControllerTestSurfaceManager: PaneCoordinatorSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>

    init() {
        self.cwdStream = AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { continuation in
            continuation.finish()
        }
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { cwdStream }

    func syncFocus(activeSurfaceId: UUID?) {}

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        .failure(.ghosttyNotInitialized)
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? {
        nil
    }

    func requeueUndo(_ surfaceId: UUID) {}

    func destroy(_ surfaceId: UUID) {}
}
