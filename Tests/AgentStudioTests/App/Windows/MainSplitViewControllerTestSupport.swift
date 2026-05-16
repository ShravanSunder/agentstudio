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

typealias MainSplitViewControllerTestSidebarBuilder =
    @MainActor (UIStateAtom, @escaping @MainActor @Sendable () -> Void) -> AnyView

@MainActor
private func makeMainSplitViewControllerHarness(
    withRepos: Bool,
    inboxAtom: InboxNotificationAtom,
    configureUIState: @MainActor (UIStateAtom) -> Void,
    configureWorkspaceMetadata: @MainActor (WorkspaceMetadataAtom) -> Void,
    sidebarRootViewBuilder: @escaping MainSplitViewControllerTestSidebarBuilder
) -> MainSplitViewControllerHarness {
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
    configureWorkspaceMetadata(atoms.workspaceMetadata)

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
        inboxAtom: inboxAtom,
        inboxPrefsAtom: InboxNotificationPrefsAtom(),
        paneInboxPresenter: PaneInboxNotificationPresenter(),
        sidebarRootViewBuilder: { dependencies in
            sidebarRootViewBuilder(dependencies.uiState, dependencies.onDismissInbox)
        },
        paneTabRegistersAsCommandHandler: false
    )
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )

    return MainSplitViewControllerHarness(
        atoms: atoms,
        store: store,
        coordinator: coordinator,
        controller: controller,
        window: window,
        tempDir: tempDir
    )
}

@MainActor
func withMainSplitViewControllerHarness<T>(
    withRepos: Bool = true,
    inboxAtom: InboxNotificationAtom = InboxNotificationAtom(),
    configureUIState: @MainActor (UIStateAtom) -> Void = { _ in },
    configureWorkspaceMetadata: @MainActor (WorkspaceMetadataAtom) -> Void = { _ in },
    sidebarRootViewBuilder: @escaping MainSplitViewControllerTestSidebarBuilder = { uiState, onEscape in
        AnyView(MainSplitViewControllerTestSidebarView(uiState: uiState, onEscape: onEscape))
    },
    body: @MainActor (MainSplitViewControllerHarness) async throws -> T
) async rethrows -> T {
    let harness = makeMainSplitViewControllerHarness(
        withRepos: withRepos,
        inboxAtom: inboxAtom,
        configureUIState: configureUIState,
        configureWorkspaceMetadata: configureWorkspaceMetadata,
        sidebarRootViewBuilder: sidebarRootViewBuilder
    )

    let result = try await AtomScope.$override.withValue(harness.atoms) {
        harness.window.contentViewController = harness.controller
        _ = harness.controller.view
        harness.window.makeKeyAndOrderFront(nil)
        return try await body(harness)
    }

    harness.controller.shutdown()
    harness.window.contentViewController = nil
    harness.window.orderOut(nil)
    await Task.yield()
    await harness.coordinator.shutdown()
    try? FileManager.default.removeItem(at: harness.tempDir)
    return result
}

@MainActor
func withUnloadedMainSplitViewControllerHarness<T>(
    withRepos: Bool = true,
    inboxAtom: InboxNotificationAtom = InboxNotificationAtom(),
    configureUIState: @MainActor (UIStateAtom) -> Void = { _ in },
    configureWorkspaceMetadata: @MainActor (WorkspaceMetadataAtom) -> Void = { _ in },
    sidebarRootViewBuilder: @escaping MainSplitViewControllerTestSidebarBuilder = { uiState, onEscape in
        AnyView(MainSplitViewControllerTestSidebarView(uiState: uiState, onEscape: onEscape))
    },
    body: @MainActor (MainSplitViewControllerHarness) async throws -> T
) async rethrows -> T {
    let harness = makeMainSplitViewControllerHarness(
        withRepos: withRepos,
        inboxAtom: inboxAtom,
        configureUIState: configureUIState,
        configureWorkspaceMetadata: configureWorkspaceMetadata,
        sidebarRootViewBuilder: sidebarRootViewBuilder
    )

    let result = try await AtomScope.$override.withValue(harness.atoms) {
        try await body(harness)
    }

    harness.controller.shutdown()
    await harness.coordinator.shutdown()
    try? FileManager.default.removeItem(at: harness.tempDir)
    return result
}

struct MainSplitViewControllerTestSidebarView: View {
    let uiState: UIStateAtom
    let onEscape: @MainActor @Sendable () -> Void

    var body: some View {
        Group {
            switch uiState.sidebarSurface {
            case .repos:
                Color.clear
            case .inbox:
                MainSplitViewControllerTestInboxView(
                    uiState: uiState,
                    onEscape: onEscape
                )
            }
        }
        .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
    }
}

final class MainSplitViewControllerTestInboxFocusableView: NSView {
    var onFocusChange: @MainActor (Bool) -> Void = { _ in }
    var onEscape: @MainActor @Sendable () -> Void = {}

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome {
            onFocusChange(true)
        }
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign {
            onFocusChange(false)
        }
        return didResign
    }

    override func cancelOperation(_ sender: Any?) {
        _ = sender
        onEscape()
    }
}

struct MainSplitViewControllerTestInboxView: NSViewRepresentable {
    let uiState: UIStateAtom
    let onEscape: @MainActor @Sendable () -> Void

    func makeNSView(context: Context) -> MainSplitViewControllerTestInboxFocusableView {
        let view = MainSplitViewControllerTestInboxFocusableView()
        view.identifier = InboxNotificationSidebarView.focusTargetIdentifier
        view.onFocusChange = { uiState.setSidebarHasFocus($0) }
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: MainSplitViewControllerTestInboxFocusableView, context: Context) {
        nsView.onFocusChange = { uiState.setSidebarHasFocus($0) }
        nsView.onEscape = onEscape
    }

    static func dismantleNSView(_ nsView: MainSplitViewControllerTestInboxFocusableView, coordinator: ()) {
        MainActor.assumeIsolated {
            nsView.onFocusChange(false)
        }
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
