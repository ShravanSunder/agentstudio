import AppKit
import Foundation
import GhosttyKit
import os.log

let paneCoordinatorLogger = Logger(subsystem: "com.agentstudio", category: "PaneCoordinator")

@MainActor
protocol PaneCoordinatorSurfaceManaging: AnyObject {
    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { get }

    func syncFocus(activeSurfaceId: UUID?)

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError>

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView?
    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason)
    func undoClose() -> ManagedSurface?
    func destroy(_ surfaceId: UUID)
}

extension SurfaceManager: PaneCoordinatorSurfaceManaging {}

@MainActor
final class PaneCoordinator {
    struct SwitchArrangementTransitions: Equatable {
        let hiddenPaneIds: Set<UUID>
        let paneIdsToReattach: Set<UUID>
    }

    let store: WorkspaceStore
    let viewRegistry: ViewRegistry
    let runtime: SessionRuntime
    let surfaceManager: PaneCoordinatorSurfaceManaging
    let runtimeRegistry: RuntimeRegistry
    let paneTargetResolver: PaneTargetResolver
    let runtimeCommandClock: ContinuousClock
    lazy var sessionConfig = SessionConfiguration.detect()
    private var cwdChangesTask: Task<Void, Never>?

    /// Unified undo stack — holds both tab and pane close entries, chronologically ordered.
    /// NOTE: Undo stack owned here (not in a store) because undo is fundamentally
    /// orchestration logic: it coordinates across WorkspaceStore, ViewRegistry, and
    /// SessionRuntime. Future: extract to UndoEngine when undo requirements grow.
    var undoStack: [WorkspaceStore.CloseEntry] = []

    /// Maximum undo stack entries before oldest are garbage-collected.
    let maxUndoStackSize = 10

    convenience init(
        store: WorkspaceStore,
        viewRegistry: ViewRegistry,
        runtime: SessionRuntime
    ) {
        self.init(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: SurfaceManager.shared,
            runtimeRegistry: RuntimeRegistry(),
            runtimeCommandClock: ContinuousClock()
        )
    }

    init(
        store: WorkspaceStore,
        viewRegistry: ViewRegistry,
        runtime: SessionRuntime,
        surfaceManager: PaneCoordinatorSurfaceManaging,
        runtimeRegistry: RuntimeRegistry,
        runtimeCommandClock: ContinuousClock = ContinuousClock()
    ) {
        self.store = store
        self.viewRegistry = viewRegistry
        self.runtime = runtime
        self.surfaceManager = surfaceManager
        self.runtimeRegistry = runtimeRegistry
        self.paneTargetResolver = PaneTargetResolver(workspaceStore: store)
        self.runtimeCommandClock = runtimeCommandClock
        subscribeToCWDChanges()
        setupPrePersistHook()
    }

    isolated deinit {
        cwdChangesTask?.cancel()
    }

    // MARK: - CWD Propagation

    private func subscribeToCWDChanges() {
        cwdChangesTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in self.surfaceManager.surfaceCWDChanges {
                if Task.isCancelled { break }
                self.onSurfaceCWDChanged(event)
            }
        }
    }

    private func onSurfaceCWDChanged(_ event: SurfaceManager.SurfaceCWDChangeEvent) {
        guard let paneId = event.paneId else { return }
        store.updatePaneCWD(paneId, cwd: event.cwd)
    }

    // MARK: - Webview State Sync

    private func setupPrePersistHook() {
        store.prePersistHook = { [weak self] in
            self?.syncWebviewStates()
        }
    }

    /// Sync runtime webview tab state back to persisted pane model.
    /// Uses syncPaneWebviewState (not updatePaneWebviewState) to avoid
    /// marking dirty during an in-flight persist, which would cause a save-loop.
    func syncWebviewStates() {
        for (paneId, webviewView) in viewRegistry.allWebviewViews {
            store.syncPaneWebviewState(paneId, state: webviewView.currentState())
        }
    }

    // MARK: - Runtime Registry

    func registerRuntime(_ runtime: any PaneRuntime) {
        runtimeRegistry.register(runtime)
    }

    @discardableResult
    func unregisterRuntime(_ paneId: PaneId) -> (any PaneRuntime)? {
        runtimeRegistry.unregister(paneId)
    }

    func runtimeForPane(_ paneId: PaneId) -> (any PaneRuntime)? {
        runtimeRegistry.runtime(for: paneId)
    }
}
