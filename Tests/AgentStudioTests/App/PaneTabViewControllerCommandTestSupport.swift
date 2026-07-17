import AppKit
import Foundation
import GhosttyKit
import SwiftUI
import Testing

@testable import AgentStudio

typealias Harness = PaneTabViewControllerCommandHarness

@MainActor
final class PaneTabViewControllerCommandLaunchRecorder {
    var openedEditors: [(id: EditorTargetId, path: URL)] = []
    var revealedPaths: [URL] = []
    var copiedPaths: [URL] = []
    var paneNoteRequests: [UUID] = []
    var clearedPaneInboxRequests: [(parentPaneId: UUID, paneIds: [UUID])] = []
}

@MainActor
struct PaneTabViewControllerCommandHarness {
    let store: WorkspaceStore
    let coordinator: WorkspaceSurfaceCoordinator
    let executor: WorkspaceActionExecutor
    let controller: PaneTabViewController
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let viewRegistry: ViewRegistry
    let runtimeRegistry: RuntimeRegistry
    let surfaceManager: MockPaneTabCommandSurfaceManager
    let windowLifecycleStore: WindowLifecycleAtom
    let tempDir: URL
    let tabRenamePopoverState: TabRenamePopoverState
    let arrangementInlineRenameState: ArrangementInlineRenameState
    let arrangementPanelPresentation: ArrangementPanelPresentationAtom
    let paneInboxPresenter: PaneInboxNotificationPresenter
    let launchRecorder: PaneTabViewControllerCommandLaunchRecorder
}

@MainActor
func makeHarness(
    createSurfaceResult: Result<ManagedSurface, SurfaceError> = .failure(.ghosttyNotInitialized),
    closeTransitionCoordinator: PaneCloseTransitionCoordinator = PaneCloseTransitionCoordinator(),
    arrangementPanelPresentation: ArrangementPanelPresentationAtom = ArrangementPanelPresentationAtom(),
    windowLifecycleStore: WindowLifecycleAtom? = nil,
    workspaceWindowId: UUID? = nil
) -> Harness {
    makePaneTabViewControllerCommandHarness(
        createSurfaceResult: createSurfaceResult,
        closeTransitionCoordinator: closeTransitionCoordinator,
        arrangementPanelPresentation: arrangementPanelPresentation,
        windowLifecycleStore: windowLifecycleStore,
        workspaceWindowId: workspaceWindowId
    )
}

@MainActor
func makePaneTabViewControllerCommandHarness(
    createSurfaceResult: Result<ManagedSurface, SurfaceError> = .failure(.ghosttyNotInitialized),
    closeTransitionCoordinator: PaneCloseTransitionCoordinator = PaneCloseTransitionCoordinator(),
    arrangementPanelPresentation: ArrangementPanelPresentationAtom = ArrangementPanelPresentationAtom(),
    windowLifecycleStore injectedWindowLifecycleStore: WindowLifecycleAtom? = nil,
    workspaceWindowId: UUID? = nil
) -> PaneTabViewControllerCommandHarness {
    // Command execution still reads the app-global management-layer atom for
    // visibility and shortcut policy. Reset it so parallel suites cannot leak
    // management mode into a fresh command harness.
    atom(\.managementLayer).deactivate()

    let tempDir = makePaneTabCommandHarnessTempDir()
    let store = WorkspaceStore()
    let viewRegistry = ViewRegistry()
    let runtime = SessionRuntime(store: store)
    let surfaceManager = MockPaneTabCommandSurfaceManager(createSurfaceResult: createSurfaceResult)
    let runtimeRegistry = RuntimeRegistry()
    let appLifecycleStore = AppLifecycleAtom()
    let windowLifecycleStore = injectedWindowLifecycleStore ?? WindowLifecycleAtom()
    let tabRenamePopoverState = TabRenamePopoverState()
    let arrangementInlineRenameState = ArrangementInlineRenameState()
    let paneInboxPresenter = PaneInboxNotificationPresenter()
    let launchRecorder = PaneTabViewControllerCommandLaunchRecorder()
    let paneInboxPresentation = makePaneTabViewControllerCommandPaneInboxPresentation(
        presenter: paneInboxPresenter,
        launchRecorder: launchRecorder
    )
    let applicationLifecycleMonitor = ApplicationLifecycleMonitor(
        appLifecycleStore: appLifecycleStore,
        windowLifecycleStore: windowLifecycleStore
    )
    let coordinator = WorkspaceSurfaceCoordinator(
        store: store,
        viewRegistry: viewRegistry,
        runtime: runtime,
        surfaceManager: surfaceManager,
        runtimeRegistry: runtimeRegistry,
        closeTransitionCoordinator: closeTransitionCoordinator,
        windowLifecycleStore: windowLifecycleStore
    )
    let executor = WorkspaceActionExecutor(coordinator: coordinator, store: store)
    let controller = PaneTabViewController(
        store: store,
        repoCache: RepoCacheAtom(),
        applicationLifecycleMonitor: applicationLifecycleMonitor,
        appLifecycleStore: appLifecycleStore,
        windowLifecycleStore: windowLifecycleStore,
        workspaceWindowId: workspaceWindowId,
        executor: executor,
        runtimeCommandDispatcher: coordinator,
        tabBarAdapter: TabBarAdapter(store: store, repoCache: RepoCacheAtom()),
        viewRegistry: viewRegistry,
        paneInboxPresentation: paneInboxPresentation,
        installedEditorTargetsProvider: { [.cursor, .vscode] },
        openEditorHandler: { editorId, path, _ in
            launchRecorder.openedEditors.append((id: editorId, path: path))
            return true
        },
        openFinderHandler: { path in
            launchRecorder.revealedPaths.append(path)
            return true
        },
        copyPathHandler: { path in
            launchRecorder.copiedPaths.append(path)
        },
        paneNotePresentation: PaneNotePresentation(
            present: { paneId in
                launchRecorder.paneNoteRequests.append(paneId)
            },
            editorContent: { _, _ in AnyView(EmptyView()) }
        ),
        closeTransitionCoordinator: closeTransitionCoordinator,
        tabRenamePopoverState: tabRenamePopoverState,
        arrangementInlineRenameState: arrangementInlineRenameState,
        arrangementPanelPresentation: arrangementPanelPresentation,
        registersAsCommandHandler: false
    )
    return PaneTabViewControllerCommandHarness(
        store: store,
        coordinator: coordinator,
        executor: executor,
        controller: controller,
        closeTransitionCoordinator: closeTransitionCoordinator,
        viewRegistry: viewRegistry,
        runtimeRegistry: runtimeRegistry,
        surfaceManager: surfaceManager,
        windowLifecycleStore: windowLifecycleStore,
        tempDir: tempDir,
        tabRenamePopoverState: tabRenamePopoverState,
        arrangementInlineRenameState: arrangementInlineRenameState,
        arrangementPanelPresentation: arrangementPanelPresentation,
        paneInboxPresenter: paneInboxPresenter,
        launchRecorder: launchRecorder
    )
}

@MainActor
private func makePaneTabViewControllerCommandPaneInboxPresentation(
    presenter paneInboxPresenter: PaneInboxNotificationPresenter,
    launchRecorder: PaneTabViewControllerCommandLaunchRecorder
) -> PaneInboxPresentation {
    PaneInboxPresentation(
        unreadCount: { _ in 0 },
        clear: { parentPaneId, paneIds in
            launchRecorder.clearedPaneInboxRequests.append((parentPaneId: parentPaneId, paneIds: paneIds))
        },
        open: { parentPaneId, paneIds in
            paneInboxPresenter.open(parentPaneId: parentPaneId, paneIds: paneIds)
        },
        openRollUpAlerts: { parentPaneId, paneIds in
            paneInboxPresenter.open(parentPaneId: parentPaneId, paneIds: paneIds)
        },
        toggle: { parentPaneId, paneIds in
            paneInboxPresenter.toggle(parentPaneId: parentPaneId, paneIds: paneIds)
        },
        setPresented: { parentPaneId, paneIds, isPresented in
            paneInboxPresenter.setPresented(parentPaneId: parentPaneId, paneIds: paneIds, isPresented: isPresented)
        },
        pendingRequest: { paneInboxPresenter.request },
        clearRequest: { request in
            paneInboxPresenter.clearRequest(request)
        },
        popoverContent: { _, _, _, _ in AnyView(EmptyView()) },
        pruneFilterModes: { _ in }
    )
}

private func makePaneTabCommandHarnessTempDir() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "agentstudio-pane-tab-command-\(UUID().uuidString)")
}

@MainActor
func configureMainWindowKeyboardOwner(_ atoms: AtomRegistry) {
    configureMainWindowKeyboardOwner(windowLifecycleStore: atoms.windowLifecycle, atoms: atoms)
}

@MainActor
func configureMainWindowKeyboardOwner(
    windowLifecycleStore: WindowLifecycleAtom,
    atoms: AtomRegistry = AtomScope.store
) {
    let windowId = UUID()
    windowLifecycleStore.recordWindowRegistered(windowId)
    windowLifecycleStore.recordWindowBecameKey(windowId)
    atoms.workspaceSidebarState.setSidebarCollapsed(false)
    atoms.workspaceSidebarState.setSidebarHasFocus(false)
    atoms.managementLayer.deactivate()
}

@MainActor
func configureMainWindowKeyboardOwner() {
    configureMainWindowKeyboardOwner(AtomScope.store)
}

@MainActor
func makeRepoAndWorktree(_ store: WorkspaceStore, root: URL) -> (Repo, Worktree) {
    makePaneTabViewControllerCommandRepoAndWorktree(store, root: root)
}

@MainActor
func makePaneTabViewControllerCommandRepoAndWorktree(
    _ store: WorkspaceStore,
    root: URL
) -> (Repo, Worktree) {
    let repoPath = root.appending(path: "repo-\(UUID().uuidString)")
    let worktreePath = repoPath.appending(path: "wt-main")
    try? FileManager.default.createDirectory(at: repoPath, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: worktreePath, withIntermediateDirectories: true)

    let repo = store.addRepo(at: repoPath)
    let worktree = Worktree(repoId: repo.id, name: "wt-main", path: worktreePath)
    store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
    return (repo, worktree)
}

@MainActor
func expectWebviewContent(_ pane: Pane, issuePrefix: String) {
    expectPaneTabViewControllerCommandWebviewContent(pane, issuePrefix: issuePrefix)
}

@MainActor
func expectPaneTabViewControllerCommandWebviewContent(_ pane: Pane, issuePrefix: String) {
    if case .webview = pane.content {
    } else {
        Issue.record("\(issuePrefix): expected created pane to be a webview")
    }
}

@MainActor
func makePaneTabViewControllerCommandWindow(
    for controller: PaneTabViewController
) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: -10_000, y: -10_000, width: 1200, height: 800),
        styleMask: [.titled],
        backing: .buffered,
        defer: true
    )
    window.contentViewController = controller
    window.makeKeyAndOrderFront(nil)
    window.contentView?.layoutSubtreeIfNeeded()
    return window
}

@MainActor
@discardableResult
func attachPaneHost(
    paneId: UUID,
    in harness: PaneTabViewControllerCommandHarness,
    to window: NSWindow,
    mountedContent: (NSView & PaneMountedContent)? = nil
) throws -> PaneHostView {
    let host = PaneHostView(paneId: paneId)
    if let mountedContent {
        host.mountContentView(mountedContent)
    }
    harness.viewRegistry.register(host, for: paneId)
    let contentView = try #require(window.contentView)
    host.frame = contentView.bounds
    contentView.addSubview(host)
    return host
}

@MainActor
final class FocusablePaneTabCommandMountedContentView: NSView, PaneMountedContent {
    override var acceptsFirstResponder: Bool { true }

    func setContentInteractionEnabled(_: Bool) {}
}

final class MockPaneTabCommandSurfaceManager: WorkspaceSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>
    private let createSurfaceResult: Result<ManagedSurface, SurfaceError>

    private(set) var createSurfaceCallCount = 0
    private(set) var lastCreatedSurfaceMetadata: SurfaceMetadata?

    init(createSurfaceResult: Result<ManagedSurface, SurfaceError>) {
        self.createSurfaceResult = createSurfaceResult
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
        createSurfaceCallCount += 1
        lastCreatedSurfaceMetadata = metadata
        return createSurfaceResult
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? { nil }

    func requeueUndo(_ surfaceId: UUID) {}

    func destroy(_ surfaceId: UUID) {}
}
