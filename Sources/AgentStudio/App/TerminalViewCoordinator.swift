import AppKit
import GhosttyKit
import os.log

private let coordinatorLogger = Logger(subsystem: "com.agentstudio", category: "TerminalViewCoordinator")

/// Owns all surface/runtime lifecycle operations.
/// Views never call SurfaceManager or SessionRuntime directly — this class is the
/// sole intermediary. TTVC dispatches actions; ActionExecutor delegates lifecycle to here.
@MainActor
final class TerminalViewCoordinator {
    private let store: WorkspaceStore
    private let viewRegistry: ViewRegistry
    private let runtime: SessionRuntime
    private lazy var sessionConfig = SessionConfiguration.detect()
    private var cwdObserver: NSObjectProtocol?

    init(store: WorkspaceStore, viewRegistry: ViewRegistry, runtime: SessionRuntime) {
        self.store = store
        self.viewRegistry = viewRegistry
        self.runtime = runtime
        subscribeToCWDNotifications()
        setupPrePersistHook()
    }

    deinit {
        if let observer = cwdObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - CWD Propagation

    private func subscribeToCWDNotifications() {
        cwdObserver = NotificationCenter.default.addObserver(
            forName: Ghostty.Notification.surfaceCWDChanged,
            object: SurfaceManager.shared,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.onSurfaceCWDChanged(notification)
            }
        }
    }

    private func onSurfaceCWDChanged(_ notification: Notification) {
        guard let surfaceId = notification.userInfo?["surfaceId"] as? UUID,
              let paneId = SurfaceManager.shared.metadata(for: surfaceId)?.paneId else {
            return
        }
        let url = notification.userInfo?["url"] as? URL
        store.updatePaneCWD(paneId, cwd: url)
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
    private func syncWebviewStates() {
        for (paneId, webviewView) in viewRegistry.allWebviewViews {
            store.syncPaneWebviewState(paneId, state: webviewView.currentState())
        }
    }

    // MARK: - Create View (content-type dispatch)

    /// Create a view for any pane content type. Dispatches to the appropriate factory.
    /// Returns the created PaneView, or nil on failure.
    @discardableResult
    func createViewForContent(pane: Pane) -> PaneView? {
        switch pane.content {
        case .terminal:
            // Main panes: have direct worktree association
            if let worktreeId = pane.worktreeId,
               let repoId = pane.repoId,
               let worktree = store.worktree(worktreeId),
               let repo = store.repo(repoId) {
                return createView(for: pane, worktree: worktree, repo: repo)

            // Drawer children: resolve worktree through parent pane
            } else if let parentPaneId = pane.parentPaneId,
                      let parentPane = store.pane(parentPaneId),
                      let worktreeId = parentPane.worktreeId,
                      let repoId = parentPane.repoId,
                      let worktree = store.worktree(worktreeId),
                      let repo = store.repo(repoId) {
                return createView(for: pane, worktree: worktree, repo: repo)

            } else {
                // Floating terminal (standalone terminals without worktree context)
                return createFloatingTerminalView(for: pane)
            }

        case .webview(let state):
            let view = WebviewPaneView(paneId: pane.id, state: state)
            let paneId = pane.id
            view.controller.onTitleChange = { [weak self] title in
                self?.store.updatePaneTitle(paneId, title: title)
            }
            viewRegistry.register(view, for: pane.id)
            coordinatorLogger.info("Created webview pane \(pane.id)")
            return view

        case .codeViewer(let state):
            let view = CodeViewerPaneView(paneId: pane.id, state: state)
            viewRegistry.register(view, for: pane.id)
            coordinatorLogger.info("Created code viewer stub for pane \(pane.id)")
            return view

        case .unsupported:
            coordinatorLogger.warning("Cannot create view for unsupported content type — pane \(pane.id)")
            return nil
        }
    }

    // MARK: - Create Terminal View

    /// Create a terminal view for a pane, including surface and runtime setup.
    /// Registers the view in the ViewRegistry.
    @discardableResult
    func createView(
        for pane: Pane,
        worktree: Worktree,
        repo: Repo
    ) -> AgentStudioTerminalView? {
        let workingDir = worktree.path

        let cmd: String
        let deferredStartupCommand: String?
        var environmentVariables: [String: String] = [:]
        switch pane.provider {
        case .zmx:
            if let zmxPath = sessionConfig.zmxPath {
                let attachCommand = buildZmxAttachCommand(
                    pane: pane,
                    worktree: worktree,
                    repo: repo,
                    zmxPath: zmxPath
                )
                // Start an interactive shell first, then inject attach after the
                // view is attached to a window and has a resolved size.
                cmd = "\(getDefaultShell()) -i -l"
                deferredStartupCommand = attachCommand
                environmentVariables["ZMX_DIR"] = sessionConfig.zmxDir
            } else {
                coordinatorLogger.warning("zmx not found, falling back to ephemeral session for \(pane.id)")
                cmd = "\(getDefaultShell()) -i -l"
                deferredStartupCommand = nil
            }
        case .ghostty:
            cmd = "\(getDefaultShell()) -i -l"
            deferredStartupCommand = nil
        case .none:
            coordinatorLogger.error("Cannot create view for non-terminal pane \(pane.id)")
            return nil
        }

        let config = Ghostty.SurfaceConfiguration(
            workingDirectory: workingDir.path,
            command: cmd,
            deferredStartupCommand: deferredStartupCommand,
            environmentVariables: environmentVariables
        )

        RestoreTrace.log(
            "createView pane=\(pane.id) provider=\(pane.provider?.rawValue ?? "none") launchMode=deferred worktree=\(worktree.name) cwd=\(workingDir.path) cmd=\(cmd) deferred=\(deferredStartupCommand ?? "nil") env=\(environmentVariables)"
        )

        let metadata = SurfaceMetadata(
            workingDirectory: workingDir,
            command: cmd,
            title: worktree.name,
            worktreeId: worktree.id,
            repoId: repo.id,
            paneId: pane.id
        )

        // Create surface via SurfaceManager
        let result = SurfaceManager.shared.createSurface(config: config, metadata: metadata)

        switch result {
        case .success(let managed):
            RestoreTrace.log(
                "createSurface success pane=\(pane.id) surface=\(managed.id) initialSurfaceFrame=\(NSStringFromRect(managed.surface.frame))"
            )
            // Attach surface
            SurfaceManager.shared.attach(managed.id, to: pane.id)

            // Create the view (it only hosts/displays, doesn't create surfaces)
            let view = AgentStudioTerminalView(
                worktree: worktree,
                repo: repo,
                restoredSurfaceId: managed.id,
                paneId: pane.id
            )
            view.displaySurface(managed.surface)

            // Register in ViewRegistry
            viewRegistry.register(view, for: pane.id)

            // Initialize runtime tracking
            runtime.markRunning(pane.id)
            RestoreTrace.log(
                "createView complete pane=\(pane.id) surface=\(managed.id) viewBounds=\(NSStringFromRect(view.bounds))"
            )

            coordinatorLogger.info("Created view for pane \(pane.id) worktree: \(worktree.name)")
            return view

        case .failure(let error):
            RestoreTrace.log("createSurface failure pane=\(pane.id) error=\(error.localizedDescription)")
            coordinatorLogger.error("Failed to create surface for pane \(pane.id): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Create Floating Terminal View

    /// Create a terminal view for a floating pane (drawers, standalone terminals).
    /// No worktree/repo context — uses home directory or pane's cwd.
    @discardableResult
    private func createFloatingTerminalView(for pane: Pane) -> AgentStudioTerminalView? {
        let workingDir = pane.metadata.cwd ?? FileManager.default.homeDirectoryForCurrentUser
        let cmd = "\(getDefaultShell()) -i -l"

        RestoreTrace.log(
            "createFloatingView pane=\(pane.id) cwd=\(workingDir.path) cmd=\(cmd)"
        )

        let config = Ghostty.SurfaceConfiguration(
            workingDirectory: workingDir.path,
            command: cmd
        )

        let metadata = SurfaceMetadata(
            workingDirectory: workingDir,
            command: cmd,
            title: pane.metadata.title,
            paneId: pane.id
        )

        let result = SurfaceManager.shared.createSurface(config: config, metadata: metadata)

        switch result {
        case .success(let managed):
            RestoreTrace.log(
                "createFloatingSurface success pane=\(pane.id) surface=\(managed.id) initialSurfaceFrame=\(NSStringFromRect(managed.surface.frame))"
            )
            SurfaceManager.shared.attach(managed.id, to: pane.id)

            let view = AgentStudioTerminalView(
                restoredSurfaceId: managed.id,
                paneId: pane.id,
                title: pane.metadata.title
            )
            view.displaySurface(managed.surface)

            viewRegistry.register(view, for: pane.id)
            runtime.markRunning(pane.id)
            RestoreTrace.log("createFloatingView complete pane=\(pane.id) surface=\(managed.id)")

            coordinatorLogger.info("Created floating terminal view for pane \(pane.id)")
            return view

        case .failure(let error):
            RestoreTrace.log("createFloatingSurface failure pane=\(pane.id) error=\(error.localizedDescription)")
            coordinatorLogger.error("Failed to create floating surface for pane \(pane.id): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Teardown View

    /// Teardown a view — detach surface (if terminal), unregister.
    func teardownView(for paneId: UUID) {
        // Terminal-specific: detach surface before unregistering
        if let terminal = viewRegistry.terminalView(for: paneId),
           let surfaceId = terminal.surfaceId {
            SurfaceManager.shared.detach(surfaceId, reason: .close)
        }

        viewRegistry.unregister(paneId)

        coordinatorLogger.debug("Tore down view for pane \(paneId)")
    }

    // MARK: - View Switch

    /// Detach a pane's surface for a view switch (hide, not destroy).
    func detachForViewSwitch(paneId: UUID) {
        if let terminal = viewRegistry.terminalView(for: paneId),
           let surfaceId = terminal.surfaceId {
            SurfaceManager.shared.detach(surfaceId, reason: .hide)
        }
        coordinatorLogger.debug("Detached pane \(paneId) for view switch")
    }

    /// Reattach a pane's surface after a view switch.
    func reattachForViewSwitch(paneId: UUID) {
        if let terminal = viewRegistry.terminalView(for: paneId),
           let surfaceId = terminal.surfaceId {
            if let surfaceView = SurfaceManager.shared.attach(surfaceId, to: paneId) {
                terminal.displaySurface(surfaceView)
            }
        }
        coordinatorLogger.debug("Reattached pane \(paneId) for view switch")
    }

    // MARK: - Undo Restore

    /// Restore a view from an undo close. Tries to reuse the undone surface; creates fresh if expired.
    @discardableResult
    func restoreView(
        for pane: Pane,
        worktree: Worktree,
        repo: Repo
    ) -> AgentStudioTerminalView? {
        // Try to undo-close the surface from SurfaceManager's undo stack
        if let undone = SurfaceManager.shared.undoClose() {
            // Verify the surface belongs to this pane before reattaching
            if undone.metadata.paneId == pane.id {
                let view = AgentStudioTerminalView(
                    worktree: worktree,
                    repo: repo,
                    restoredSurfaceId: undone.id,
                    paneId: pane.id
                )
                SurfaceManager.shared.attach(undone.id, to: pane.id)
                view.displaySurface(undone.surface)
                viewRegistry.register(view, for: pane.id)
                runtime.markRunning(pane.id)
                coordinatorLogger.info("Restored view from undo for pane \(pane.id)")
                return view
            } else {
                coordinatorLogger.warning(
                    "Undo surface metadata mismatch: expected pane \(pane.id), got \(undone.metadata.paneId?.uuidString ?? "nil") — creating fresh"
                )
                // Surface doesn't belong to this pane; destroy it and create fresh
                SurfaceManager.shared.destroy(undone.id)
            }
        }

        // Undo expired or mismatched — create fresh (zmx reattaches, content preserved)
        coordinatorLogger.info("Creating fresh view for pane \(pane.id)")
        return createView(for: pane, worktree: worktree, repo: repo)
    }

    // MARK: - Restore All Views

    /// Recreate views for all restored panes in all tabs, including drawer panes.
    /// Called once at launch after store.restore() populates persisted state.
    func restoreAllViews() {
        // Use tab.panes (all owned panes) instead of tab.paneIds (active arrangement only)
        // to ensure panes in non-active arrangements also get views restored.
        let paneIds = store.tabs.flatMap(\.panes)
        RestoreTrace.log(
            "restoreAllViews begin tabs=\(store.tabs.count) paneIds=\(paneIds.count) activeTab=\(store.activeTabId?.uuidString ?? "nil")"
        )
        guard !paneIds.isEmpty else {
            coordinatorLogger.info("No panes to restore views for")
            RestoreTrace.log("restoreAllViews no panes")
            return
        }

        var restored = 0
        var drawerRestored = 0
        for paneId in paneIds {
            guard let pane = store.pane(paneId) else {
                coordinatorLogger.warning("Skipping view restore for pane \(paneId) — not in store")
                RestoreTrace.log("restoreAllViews skip missing pane=\(paneId)")
                continue
            }
            RestoreTrace.log("restoreAllViews restoring pane=\(paneId) content=\(String(describing: pane.content))")
            if createViewForContent(pane: pane) != nil {
                restored += 1
            }

            // Also restore views for drawer panes owned by this pane
            if let drawer = pane.drawer {
                for drawerPaneId in drawer.paneIds {
                    guard let drawerPane = store.pane(drawerPaneId) else { continue }
                    RestoreTrace.log("restoreAllViews restoring drawer pane=\(drawerPaneId) parent=\(pane.id)")
                    if createViewForContent(pane: drawerPane) != nil {
                        drawerRestored += 1
                    }
                }
            }
        }
        coordinatorLogger.info("Restored \(restored)/\(paneIds.count) pane views, \(drawerRestored) drawer pane views")

        // Sync focus after all views are restored — only the active terminal gets a blinking cursor.
        if let activeTab = store.activeTab,
           let activePaneId = activeTab.activePaneId,
           let terminalView = viewRegistry.terminalView(for: activePaneId) {
            SurfaceManager.shared.syncFocus(activeSurfaceId: terminalView.surfaceId)
            RestoreTrace.log(
                "restoreAllViews syncFocus activeTab=\(activeTab.id) activePane=\(activePaneId) activeSurface=\(terminalView.surfaceId?.uuidString ?? "nil")"
            )
        }
        RestoreTrace.log("restoreAllViews end restored=\(restored) drawerRestored=\(drawerRestored)")
    }

    // MARK: - Helpers

    private func buildZmxAttachCommand(pane: Pane, worktree: Worktree, repo: Repo, zmxPath: String) -> String {
        let zmxSessionName: String
        if let parentPaneId = pane.parentPaneId {
            // Drawer pane: session ID based on parent + drawer pane UUIDs
            zmxSessionName = ZmxBackend.drawerSessionId(parentPaneId: parentPaneId, drawerPaneId: pane.id)
        } else {
            // Main pane: session ID based on repo + worktree stable keys
            zmxSessionName = ZmxBackend.sessionId(
                repoStableKey: repo.stableKey,
                worktreeStableKey: worktree.stableKey,
                paneId: pane.id
            )
        }
        RestoreTrace.log(
            "buildZmxAttachCommand pane=\(pane.id) session=\(zmxSessionName) zmxPath=\(zmxPath) zmxDir=\(sessionConfig.zmxDir)"
        )
        return ZmxBackend.buildAttachCommand(
            zmxPath: zmxPath,
            sessionId: zmxSessionName,
            shell: getDefaultShell()
        )
    }

    private func getDefaultShell() -> String {
        SessionConfiguration.defaultShell()
    }
}
