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

    init(store: WorkspaceStore, viewRegistry: ViewRegistry, runtime: SessionRuntime) {
        self.store = store
        self.viewRegistry = viewRegistry
        self.runtime = runtime
    }

    // MARK: - Create View

    /// Create a terminal view for a session, including surface and runtime setup.
    /// Registers the view in the ViewRegistry.
    @discardableResult
    func createView(
        for session: TerminalSession,
        worktree: Worktree,
        repo: Repo
    ) -> AgentStudioTerminalView? {
        let workingDir = worktree.path

        let cmd: String
        switch session.provider {
        case .tmux:
            cmd = buildTmuxAttachCommand(session: session, worktree: worktree, repo: repo)
        case .ghostty:
            cmd = "\(getDefaultShell()) -i -l"
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
            sessionId: session.id
        )

        // Create surface via SurfaceManager
        let result = SurfaceManager.shared.createSurface(config: config, metadata: metadata)

        switch result {
        case .success(let managed):
            // Attach surface
            SurfaceManager.shared.attach(managed.id, to: session.id)

            // Create the view (it only hosts/displays, doesn't create surfaces)
            let view = AgentStudioTerminalView(
                worktree: worktree,
                repo: repo,
                restoredSurfaceId: managed.id,
                sessionId: session.id
            )
            view.displaySurface(managed.surface)

            // Register in ViewRegistry
            viewRegistry.register(view, for: session.id)

            // Initialize runtime tracking
            runtime.markRunning(session.id)

            coordinatorLogger.info("Created view for session \(session.id) worktree: \(worktree.name)")
            return view

        case .failure(let error):
            coordinatorLogger.error("Failed to create surface for session \(session.id): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Teardown View

    /// Teardown a terminal view — detach surface, suspend runtime, unregister.
    func teardownView(for sessionId: UUID) {
        // Get the view's surfaceId before unregistering
        if let view = viewRegistry.view(for: sessionId), let surfaceId = view.surfaceId {
            SurfaceManager.shared.detach(surfaceId, reason: .close)
        }

        viewRegistry.unregister(sessionId)

        coordinatorLogger.debug("Tore down view for session \(sessionId)")
    }

    // MARK: - View Switch

    /// Detach a session's surface for a view switch (hide, not destroy).
    func detachForViewSwitch(sessionId: UUID) {
        if let view = viewRegistry.view(for: sessionId), let surfaceId = view.surfaceId {
            SurfaceManager.shared.detach(surfaceId, reason: .hide)
        }
        coordinatorLogger.debug("Detached session \(sessionId) for view switch")
    }

    /// Reattach a session's surface after a view switch.
    func reattachForViewSwitch(sessionId: UUID) {
        if let view = viewRegistry.view(for: sessionId), let surfaceId = view.surfaceId {
            if let surfaceView = SurfaceManager.shared.attach(surfaceId, to: sessionId) {
                view.displaySurface(surfaceView)
            }
        }
        coordinatorLogger.debug("Reattached session \(sessionId) for view switch")
    }

    // MARK: - Undo Restore

    /// Restore a view from an undo close. Tries to reuse the undone surface; creates fresh if expired.
    /// SurfaceManager.undoClose() is a global LIFO stack. We verify metadata.sessionId matches
    /// before reattaching to avoid assigning the wrong surface (e.g., in multi-pane tab undo).
    /// TODO: Add keyed undo to SurfaceManager so the correct surface is always returned (Phase 4).
    @discardableResult
    func restoreView(
        for session: TerminalSession,
        worktree: Worktree,
        repo: Repo
    ) -> AgentStudioTerminalView? {
        // Try to undo-close the surface from SurfaceManager's undo stack
        if let undone = SurfaceManager.shared.undoClose() {
            // Verify the surface belongs to this session before reattaching
            if undone.metadata.sessionId == session.id {
                let view = AgentStudioTerminalView(
                    worktree: worktree,
                    repo: repo,
                    restoredSurfaceId: undone.id,
                    sessionId: session.id
                )
                SurfaceManager.shared.attach(undone.id, to: session.id)
                view.displaySurface(undone.surface)
                viewRegistry.register(view, for: session.id)
                runtime.markRunning(session.id)
                coordinatorLogger.info("Restored view from undo for session \(session.id)")
                return view
            } else {
                coordinatorLogger.warning(
                    "Undo surface metadata mismatch: expected session \(session.id), got \(undone.metadata.sessionId?.uuidString ?? "nil") — creating fresh"
                )
                // Surface doesn't belong to this session; destroy it and create fresh
                SurfaceManager.shared.destroy(undone.id)
            }
        }

        // Undo expired or mismatched — create fresh (tmux reattaches, content preserved)
        coordinatorLogger.info("Creating fresh view for session \(session.id)")
        return createView(for: session, worktree: worktree, repo: repo)
    }

    // MARK: - Restore All Views

    /// Recreate terminal views for all restored sessions in the active view.
    /// Called once at launch after store.restore() populates persisted state.
    func restoreAllViews() {
        let sessionIds = store.activeView?.allSessionIds ?? []
        guard !sessionIds.isEmpty else {
            coordinatorLogger.info("No sessions to restore views for")
            return
        }

        var restored = 0
        for sessionId in sessionIds {
            guard let session = store.session(sessionId),
                  let worktreeId = session.worktreeId,
                  let repoId = session.repoId,
                  let worktree = store.worktree(worktreeId),
                  let repo = store.repo(repoId) else {
                coordinatorLogger.warning("Skipping view restore for session \(sessionId) — missing worktree/repo")
                continue
            }
            if createView(for: session, worktree: worktree, repo: repo) != nil {
                restored += 1
            }
        }
        coordinatorLogger.info("Restored \(restored)/\(sessionIds.count) terminal views")
    }

    // MARK: - Helpers

    private func buildTmuxAttachCommand(session: TerminalSession, worktree: Worktree, repo: Repo) -> String {
        let tmuxSessionName = TmuxBackend.sessionId(
            repoStableKey: repo.stableKey,
            worktreeStableKey: worktree.stableKey,
            paneId: session.id
        )
        let escapedConfig = TmuxBackend.shellEscape(sessionConfig.ghostConfigPath)
        let escapedCwd = TmuxBackend.shellEscape(worktree.path.path)
        let escapedName = TmuxBackend.shellEscape(tmuxSessionName)
        return "tmux -L \(TmuxBackend.socketName) -f \(escapedConfig) new-session -A -s \(escapedName) -c \(escapedCwd)"
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
