import AppKit
import Foundation
import GhosttyKit
import SwiftUI

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInboxNotification
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

@MainActor
struct MainSplitViewControllerHarness {
    let atoms: AtomRegistry
    let store: WorkspaceStore
    let coordinator: WorkspaceSurfaceCoordinator
    let controller: MainSplitViewController
    let window: NSWindow
    let tempDir: URL
}

typealias MainSplitViewControllerTestSidebarBuilder =
    @MainActor (WorkspaceSidebarState, @escaping @MainActor @Sendable () -> Void) -> AnyView

@MainActor
private func makeMainSplitViewControllerHarness(
    withRepos: Bool,
    inboxAtom: InboxNotificationAtom,
    paneTabRegistersAsCommandHandler: Bool,
    configureUIState: @MainActor (WorkspaceSidebarState) -> Void,
    configureWorkspaceWindowMemory: @MainActor (WorkspaceWindowMemoryAtom) -> Void,
    sidebarRootViewBuilder: @escaping MainSplitViewControllerTestSidebarBuilder
) -> MainSplitViewControllerHarness {
    let tempDir = FileManager.default.temporaryDirectory
        .appending(path: "main-split-view-controller-tests-\(UUID().uuidString)")
    let atoms = makeTestAtomRegistry()
    configureUIState(atoms.core.workspaceSidebarState)

    let store = WorkspaceStore(
        identityAtom: atoms.core.workspaceIdentity,
        windowMemoryAtom: atoms.core.workspaceWindowMemory,
        repositoryTopologyAtom: atoms.core.workspaceRepositoryTopology,
        paneAtom: atoms.core.workspacePane,
        tabLayoutAtom: atoms.core.workspaceTabLayout,
        mutationCoordinator: atoms.core.workspaceMutationCoordinator)
    configureWorkspaceWindowMemory(atoms.core.workspaceWindowMemory)

    if withRepos {
        _ = store.addRepo(at: tempDir.appending(path: "repo"))
    }

    let viewRegistry = ViewRegistry()
    let runtime = SessionRuntime(atom: atoms.core.sessionRuntime, store: store)
    let coordinator = WorkspaceSurfaceCoordinator(
        store: store,
        viewRegistry: viewRegistry,
        runtime: runtime,
        surfaceManager: MainSplitViewControllerTestSurfaceManager(),
        runtimeRegistry: RuntimeRegistry(),
        windowLifecycleStore: WindowLifecycleAtom(),
        bridgePaneAttendance: atoms.bridgePaneAttendance
    )
    let workspaceActionExecutor = WorkspaceActionExecutor(coordinator: coordinator, store: store)
    let appLifecycleStore = AppLifecycleAtom()
    let applicationLifecycleMonitor = ApplicationLifecycleMonitor(
        appLifecycleStore: appLifecycleStore,
        windowLifecycleStore: WindowLifecycleAtom()
    )
    let tabBarAdapter = TabBarAdapter(
        store: store,
        repoCache: atoms.core.repoCache,
        inboxAtom: inboxAtom
    )
    let controller = MainSplitViewController(
        store: store,
        octiconLoader: makeTestOcticonLoader(),
        workspaceActionExecutor: workspaceActionExecutor,
        runtimeCommandDispatcher: coordinator,
        applicationLifecycleMonitor: applicationLifecycleMonitor,
        appLifecycleStore: appLifecycleStore,
        tabBarAdapter: tabBarAdapter,
        viewRegistry: viewRegistry,
        inboxAtom: inboxAtom,
        inboxPrefsAtom: atoms.inboxNotificationPrefs,
        inboxSidebarState: atoms.inboxSidebarState,
        paneInboxPresentationState: atoms.paneInboxPresentationState,
        repoExplorerSidebarPrefs: atoms.repoExplorerSidebarPrefs,
        bridgeAttendanceSnapshot: { paneId in
            atoms.bridgePaneAttendance.ordinal(for: paneId)
        },
        bridgePaneAttendance: atoms.bridgePaneAttendance,
        editorChooser: atoms.editorChooser,
        paneInboxPresenter: PaneInboxNotificationPresenter(),
        sidebarRootViewBuilder: { dependencies in
            sidebarRootViewBuilder(dependencies.uiState, dependencies.onDismissInbox)
        },
        paneTabRegistersAsCommandHandler: paneTabRegistersAsCommandHandler
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
    paneTabRegistersAsCommandHandler: Bool = false,
    configureUIState: @MainActor (WorkspaceSidebarState) -> Void = { _ in },
    configureWorkspaceWindowMemory: @MainActor (WorkspaceWindowMemoryAtom) -> Void = { _ in },
    sidebarRootViewBuilder: @escaping MainSplitViewControllerTestSidebarBuilder = { uiState, onEscape in
        AnyView(MainSplitViewControllerTestSidebarView(uiState: uiState, onEscape: onEscape))
    },
    body: @MainActor (MainSplitViewControllerHarness) async throws -> T
) async rethrows -> T {
    let harness = makeMainSplitViewControllerHarness(
        withRepos: withRepos,
        inboxAtom: inboxAtom,
        paneTabRegistersAsCommandHandler: paneTabRegistersAsCommandHandler,
        configureUIState: configureUIState,
        configureWorkspaceWindowMemory: configureWorkspaceWindowMemory,
        sidebarRootViewBuilder: sidebarRootViewBuilder
    )

    let result = try await withAsyncTestCoreAtoms(using: harness.atoms.core) { _ in
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
    configureUIState: @MainActor (WorkspaceSidebarState) -> Void = { _ in },
    configureWorkspaceWindowMemory: @MainActor (WorkspaceWindowMemoryAtom) -> Void = { _ in },
    sidebarRootViewBuilder: @escaping MainSplitViewControllerTestSidebarBuilder = { uiState, onEscape in
        AnyView(MainSplitViewControllerTestSidebarView(uiState: uiState, onEscape: onEscape))
    },
    body: @MainActor (MainSplitViewControllerHarness) async throws -> T
) async rethrows -> T {
    let harness = makeMainSplitViewControllerHarness(
        withRepos: withRepos,
        inboxAtom: inboxAtom,
        paneTabRegistersAsCommandHandler: false,
        configureUIState: configureUIState,
        configureWorkspaceWindowMemory: configureWorkspaceWindowMemory,
        sidebarRootViewBuilder: sidebarRootViewBuilder
    )

    let result = try await withAsyncTestCoreAtoms(using: harness.atoms.core) { _ in
        try await body(harness)
    }

    harness.controller.shutdown()
    await harness.coordinator.shutdown()
    try? FileManager.default.removeItem(at: harness.tempDir)
    return result
}

struct MainSplitViewControllerTestSidebarView: View {
    let uiState: WorkspaceSidebarState
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
    let uiState: WorkspaceSidebarState
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

private final class MainSplitViewControllerTestSurfaceManager: WorkspaceSurfaceManaging {
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
