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

    // MARK: - Create View (content-type dispatch)

    /// Create a view for any pane content type. Dispatches to the appropriate factory.
    /// Returns the created PaneView, or nil on failure.
    @discardableResult
    func createViewForContent(pane: Pane) -> PaneView? {
        switch pane.content {
        case .terminal:
            // Terminal panes require worktree/repo context for surface creation
            guard let worktreeId = pane.worktreeId,
                  let repoId = pane.repoId,
                  let worktree = store.worktree(worktreeId),
                  let repo = store.repo(repoId) else {
                coordinatorLogger.warning("Cannot create terminal view — pane \(pane.id) has no worktree/repo context")
                return nil
            }
            return createView(for: pane, worktree: worktree, repo: repo)

        case .webview(let state):
            let view = WebviewPaneView(paneId: pane.id, state: state)
            viewRegistry.register(view, for: pane.id)
            coordinatorLogger.info("Created webview stub for pane \(pane.id)")
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
        switch pane.provider {
        case .tmux:
            cmd = buildTmuxAttachCommand(pane: pane, worktree: worktree, repo: repo)
        case .ghostty:
            cmd = "\(getDefaultShell()) -i -l"
        case .none:
            coordinatorLogger.error("Cannot create view for non-terminal pane \(pane.id)")
            return nil
        }

        let config = Ghostty.SurfaceConfiguration(
            workingDirectory: workingDir.path,
            command: cmd
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

            coordinatorLogger.info("Created view for pane \(pane.id) worktree: \(worktree.name)")
            return view

        case .failure(let error):
            coordinatorLogger.error("Failed to create surface for pane \(pane.id): \(error.localizedDescription)")
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

        // Undo expired or mismatched — create fresh (tmux reattaches, content preserved)
        coordinatorLogger.info("Creating fresh view for pane \(pane.id)")
        return createView(for: pane, worktree: worktree, repo: repo)
    }

    // MARK: - Restore All Views

    /// Recreate views for all restored panes in all tabs.
    /// Called once at launch after store.restore() populates persisted state.
    func restoreAllViews() {
        let paneIds = store.tabs.flatMap(\.paneIds)
        guard !paneIds.isEmpty else {
            coordinatorLogger.info("No panes to restore views for")
            return
        }

        var restored = 0
        for paneId in paneIds {
            guard let pane = store.pane(paneId) else {
                coordinatorLogger.warning("Skipping view restore for pane \(paneId) — not in store")
                continue
            }
            if createViewForContent(pane: pane) != nil {
                restored += 1
            }
        }
        coordinatorLogger.info("Restored \(restored)/\(paneIds.count) pane views")

        // Sync focus after all views are restored — only the active terminal gets a blinking cursor.
        if let activeTab = store.activeTab,
           let activePaneId = activeTab.activePaneId,
           let terminalView = viewRegistry.terminalView(for: activePaneId) {
            SurfaceManager.shared.syncFocus(activeSurfaceId: terminalView.surfaceId)
        }
    }

    // MARK: - Helpers

    private func buildTmuxAttachCommand(pane: Pane, worktree: Worktree, repo: Repo) -> String {
        let tmuxSessionName = TmuxBackend.sessionId(
            repoStableKey: repo.stableKey,
            worktreeStableKey: worktree.stableKey,
            paneId: pane.id
        )
        let tmuxBin = sessionConfig.tmuxPath ?? "tmux"
        return TmuxBackend.buildAttachCommand(
            tmuxBin: tmuxBin,
            socketName: TmuxBackend.socketName,
            ghostConfigPath: sessionConfig.ghostConfigPath,
            sessionId: tmuxSessionName,
            workingDirectory: worktree.path.path
        )
    }

    private func getDefaultShell() -> String {
        if let pw = getpwuid(getuid()), let shell = pw.pointee.pw_shell {
            return String(cString: shell)
        }
        if let envShell = ProcessInfo.processInfo.environment["SHELL"] {
            return envShell
        }
        return "/bin/zsh"
    }
}
