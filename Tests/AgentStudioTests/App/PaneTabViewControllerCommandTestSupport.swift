import AppKit
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

typealias Harness = PaneTabViewControllerCommandHarness

@MainActor
final class PaneTabViewControllerCommandLaunchRecorder {
    var openedEditors: [(id: EditorTargetId, path: URL)] = []
    var revealedPaths: [URL] = []
}

@MainActor
struct PaneTabViewControllerCommandHarness {
    let store: WorkspaceStore
    let coordinator: PaneCoordinator
    let executor: ActionExecutor
    let controller: PaneTabViewController
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let viewRegistry: ViewRegistry
    let surfaceManager: MockPaneTabCommandSurfaceManager
    let windowLifecycleStore: WindowLifecycleAtom
    let tempDir: URL
    let tabRenamePopoverState: TabRenamePopoverState
    let arrangementInlineRenameState: ArrangementInlineRenameState
    let launchRecorder: PaneTabViewControllerCommandLaunchRecorder
}

@MainActor
func makeHarness(
    createSurfaceResult: Result<ManagedSurface, SurfaceError> = .failure(.ghosttyNotInitialized),
    closeTransitionCoordinator: PaneCloseTransitionCoordinator = PaneCloseTransitionCoordinator()
) -> Harness {
    makePaneTabViewControllerCommandHarness(
        createSurfaceResult: createSurfaceResult,
        closeTransitionCoordinator: closeTransitionCoordinator
    )
}

@MainActor
func makePaneTabViewControllerCommandHarness(
    createSurfaceResult: Result<ManagedSurface, SurfaceError> = .failure(.ghosttyNotInitialized),
    closeTransitionCoordinator: PaneCloseTransitionCoordinator = PaneCloseTransitionCoordinator()
) -> PaneTabViewControllerCommandHarness {
    let tempDir = FileManager.default.temporaryDirectory
        .appending(path: "agentstudio-pane-tab-command-\(UUID().uuidString)")
    let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
    store.restore()
    let viewRegistry = ViewRegistry()
    let runtime = SessionRuntime(store: store)
    let surfaceManager = MockPaneTabCommandSurfaceManager(createSurfaceResult: createSurfaceResult)
    let runtimeRegistry = RuntimeRegistry()
    let appLifecycleStore = AppLifecycleAtom()
    let windowLifecycleStore = WindowLifecycleAtom()
    let tabRenamePopoverState = TabRenamePopoverState()
    let arrangementInlineRenameState = ArrangementInlineRenameState()
    let launchRecorder = PaneTabViewControllerCommandLaunchRecorder()
    let applicationLifecycleMonitor = ApplicationLifecycleMonitor(
        appLifecycleStore: appLifecycleStore,
        windowLifecycleStore: windowLifecycleStore
    )
    let coordinator = PaneCoordinator(
        store: store,
        viewRegistry: viewRegistry,
        runtime: runtime,
        surfaceManager: surfaceManager,
        runtimeRegistry: runtimeRegistry,
        closeTransitionCoordinator: closeTransitionCoordinator,
        windowLifecycleStore: windowLifecycleStore
    )
    let executor = ActionExecutor(coordinator: coordinator, store: store)
    let controller = PaneTabViewController(
        store: store,
        repoCache: RepoCacheAtom(),
        applicationLifecycleMonitor: applicationLifecycleMonitor,
        appLifecycleStore: appLifecycleStore,
        executor: executor,
        tabBarAdapter: TabBarAdapter(store: store, repoCache: RepoCacheAtom()),
        viewRegistry: viewRegistry,
        installedEditorTargetsProvider: { [.cursor, .vscode] },
        openEditorHandler: { editorId, path, _ in
            launchRecorder.openedEditors.append((id: editorId, path: path))
            return true
        },
        openFinderHandler: { path in
            launchRecorder.revealedPaths.append(path)
            return true
        },
        closeTransitionCoordinator: closeTransitionCoordinator,
        tabRenamePopoverState: tabRenamePopoverState,
        arrangementInlineRenameState: arrangementInlineRenameState
    )
    return PaneTabViewControllerCommandHarness(
        store: store,
        coordinator: coordinator,
        executor: executor,
        controller: controller,
        closeTransitionCoordinator: closeTransitionCoordinator,
        viewRegistry: viewRegistry,
        surfaceManager: surfaceManager,
        windowLifecycleStore: windowLifecycleStore,
        tempDir: tempDir,
        tabRenamePopoverState: tabRenamePopoverState,
        arrangementInlineRenameState: arrangementInlineRenameState,
        launchRecorder: launchRecorder
    )
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

final class MockPaneTabCommandSurfaceManager: PaneCoordinatorSurfaceManaging {
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
