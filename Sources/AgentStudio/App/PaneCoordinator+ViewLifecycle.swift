import AppKit
import Foundation
import GhosttyKit

@MainActor
extension PaneCoordinator {
    /// Create a view for any pane content type. Dispatches to the appropriate factory.
    /// Returns the created PaneView, or nil on failure.
    func createViewForContent(pane: Pane) -> PaneView? {
        switch pane.content {
        case .terminal:
            if let worktreeId = pane.worktreeId,
                let repoId = pane.repoId,
                let worktree = store.worktree(worktreeId),
                let repo = store.repo(repoId)
            {
                return createView(for: pane, worktree: worktree, repo: repo)

            } else if let parentPaneId = pane.parentPaneId,
                let parentPane = store.pane(parentPaneId),
                let worktreeId = parentPane.worktreeId,
                let repoId = parentPane.repoId,
                let worktree = store.worktree(worktreeId),
                let repo = store.repo(repoId)
            {
                return createView(for: pane, worktree: worktree, repo: repo)

            } else {
                return createFloatingTerminalView(for: pane)
            }

        case .webview(let state):
            let view = WebviewPaneView(paneId: pane.id, state: state)
            let paneId = pane.id
            view.controller.onTitleChange = { [weak self] title in
                self?.store.updatePaneTitle(paneId, title: title)
            }
            viewRegistry.register(view, for: pane.id)
            paneCoordinatorLogger.info("Created webview pane \(pane.id)")
            return view

        case .codeViewer(let state):
            let view = CodeViewerPaneView(paneId: pane.id, state: state)
            viewRegistry.register(view, for: pane.id)
            paneCoordinatorLogger.info("Created code viewer stub for pane \(pane.id)")
            return view

        case .bridgePanel(let state):
            let controller = BridgePaneController(paneId: pane.id, state: state)
            let view = BridgePaneView(paneId: pane.id, controller: controller)
            viewRegistry.register(view, for: pane.id)
            controller.loadApp()
            paneCoordinatorLogger.info("Created bridge panel view for pane \(pane.id)")
            return view

        case .unsupported:
            paneCoordinatorLogger.warning("Cannot create view for unsupported content type — pane \(pane.id)")
            return nil
        }
    }

    /// Create a terminal view for a pane, including surface and runtime setup.
    /// Registers the view in the ViewRegistry.
    @discardableResult
    func createView(
        for pane: Pane,
        worktree: Worktree,
        repo: Repo
    ) -> AgentStudioTerminalView? {
        let workingDir = worktree.path

        let shellCommand = "\(getDefaultShell()) -i -l"
        let startupStrategy: Ghostty.SurfaceStartupStrategy
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
                startupStrategy = .deferredInShell(command: attachCommand)
                environmentVariables["ZMX_DIR"] = sessionConfig.zmxDir
            } else {
                paneCoordinatorLogger.error(
                    "zmx not found; using ephemeral session for \(pane.id) (state will not persist)"
                )
                if !pane.metadata.title.localizedCaseInsensitiveContains("ephemeral") {
                    store.updatePaneTitle(pane.id, title: "\(pane.metadata.title) [ephemeral]")
                }
                startupStrategy = .surfaceCommand(shellCommand)
            }
        case .ghostty:
            startupStrategy = .surfaceCommand(shellCommand)
        case .none:
            paneCoordinatorLogger.error("Cannot create view for non-terminal pane \(pane.id)")
            return nil
        }

        let config = Ghostty.SurfaceConfiguration(
            workingDirectory: workingDir.path,
            startupStrategy: startupStrategy,
            environmentVariables: environmentVariables
        )

        let metadata = SurfaceMetadata(
            workingDirectory: workingDir,
            command: shellCommand,
            title: worktree.name,
            worktreeId: worktree.id,
            repoId: repo.id,
            paneId: pane.id
        )

        let result = surfaceManager.createSurface(config: config, metadata: metadata)

        switch result {
        case .success(let managed):
            RestoreTrace.log(
                "createView success pane=\(pane.id) surface=\(managed.id) initialSurfaceFrame=\(NSStringFromRect(managed.surface.frame))"
            )
            surfaceManager.attach(managed.id, to: pane.id)

            let view = AgentStudioTerminalView(
                worktree: worktree,
                repo: repo,
                restoredSurfaceId: managed.id,
                paneId: pane.id
            )
            view.displaySurface(managed.surface)

            viewRegistry.register(view, for: pane.id)
            runtime.markRunning(pane.id)
            RestoreTrace.log(
                "createView complete pane=\(pane.id) surface=\(managed.id) viewBounds=\(NSStringFromRect(view.bounds))"
            )

            paneCoordinatorLogger.info("Created view for pane \(pane.id) worktree: \(worktree.name)")
            return view

        case .failure(let error):
            RestoreTrace.log(
                "createSurface failure pane=\(pane.id) error=\(error.localizedDescription)"
            )
            paneCoordinatorLogger.error("Failed to create surface for pane \(pane.id): \(error.localizedDescription)")
            return nil
        }
    }

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
            startupStrategy: .surfaceCommand(cmd)
        )

        let metadata = SurfaceMetadata(
            workingDirectory: workingDir,
            command: cmd,
            title: pane.metadata.title,
            paneId: pane.id
        )

        let result = surfaceManager.createSurface(config: config, metadata: metadata)

        switch result {
        case .success(let managed):
            RestoreTrace.log(
                "createFloatingSurface success pane=\(pane.id) surface=\(managed.id) initialSurfaceFrame=\(NSStringFromRect(managed.surface.frame))"
            )
            surfaceManager.attach(managed.id, to: pane.id)

            let view = AgentStudioTerminalView(
                restoredSurfaceId: managed.id,
                paneId: pane.id,
                title: pane.metadata.title
            )
            view.displaySurface(managed.surface)

            viewRegistry.register(view, for: pane.id)
            runtime.markRunning(pane.id)
            RestoreTrace.log("createFloatingView complete pane=\(pane.id) surface=\(managed.id)")

            paneCoordinatorLogger.info("Created floating terminal view for pane \(pane.id)")
            return view

        case .failure(let error):
            RestoreTrace.log(
                "createFloatingSurface failure pane=\(pane.id) error=\(error.localizedDescription)"
            )
            paneCoordinatorLogger.error(
                "Failed to create floating surface for pane \(pane.id): \(error.localizedDescription)")
            return nil
        }
    }

    /// Teardown a view — detach surface (if terminal), unregister.
    func teardownView(for paneId: UUID, shouldUnregisterRuntime: Bool = true) {
        if let terminal = viewRegistry.terminalView(for: paneId),
            let surfaceId = terminal.surfaceId
        {
            surfaceManager.detach(surfaceId, reason: .close)
        }

        if let bridgeView = viewRegistry.view(for: paneId) as? BridgePaneView {
            bridgeView.controller.teardown()
        }

        viewRegistry.unregister(paneId)
        if shouldUnregisterRuntime {
            _ = unregisterRuntime(PaneId(uuid: paneId))
            runtime.removeSession(paneId)
        }

        paneCoordinatorLogger.debug("Tore down view for pane \(paneId)")
    }

    /// Detach a pane's surface for a view switch (hide, not destroy).
    func detachForViewSwitch(paneId: UUID) {
        if let terminal = viewRegistry.terminalView(for: paneId),
            let surfaceId = terminal.surfaceId
        {
            surfaceManager.detach(surfaceId, reason: .hide)
        }
        paneCoordinatorLogger.debug("Detached pane \(paneId) for view switch")
    }

    /// Reattach a pane's surface after a view switch.
    func reattachForViewSwitch(paneId: UUID) {
        if let terminal = viewRegistry.terminalView(for: paneId),
            let surfaceId = terminal.surfaceId
        {
            if let surfaceView = surfaceManager.attach(surfaceId, to: paneId) {
                terminal.displaySurface(surfaceView)
            }
        }
        paneCoordinatorLogger.debug("Reattached pane \(paneId) for view switch")
    }

    /// Restore a view from an undo close. Tries to reuse the undone surface; creates fresh if expired.
    @discardableResult
    func restoreView(
        for pane: Pane,
        worktree: Worktree,
        repo: Repo
    ) -> AgentStudioTerminalView? {
        if let undone = surfaceManager.undoClose() {
            if undone.metadata.paneId == pane.id {
                let view = AgentStudioTerminalView(
                    worktree: worktree,
                    repo: repo,
                    restoredSurfaceId: undone.id,
                    paneId: pane.id
                )
                surfaceManager.attach(undone.id, to: pane.id)
                view.displaySurface(undone.surface)
                viewRegistry.register(view, for: pane.id)
                runtime.markRunning(pane.id)
                paneCoordinatorLogger.info("Restored view from undo for pane \(pane.id)")
                return view
            } else {
                paneCoordinatorLogger.warning(
                    "Undo surface metadata mismatch: expected pane \(pane.id), got \(undone.metadata.paneId?.uuidString ?? "nil") — creating fresh"
                )
                surfaceManager.requeueUndo(undone.id)
            }
        }

        paneCoordinatorLogger.info("Creating fresh view for pane \(pane.id)")
        return createView(for: pane, worktree: worktree, repo: repo)
    }

    /// Recreate views for all restored panes in all tabs, including drawer panes.
    /// Called once at launch after store.restore() populates persisted state.
    func restoreAllViews() {
        let paneIds = store.tabs.flatMap(\.panes)
        RestoreTrace.log(
            "restoreAllViews begin tabs=\(store.tabs.count) paneIds=\(paneIds.count) activeTab=\(store.activeTabId?.uuidString ?? "nil")"
        )
        guard !paneIds.isEmpty else {
            paneCoordinatorLogger.info("No panes to restore views for")
            RestoreTrace.log("restoreAllViews no panes")
            return
        }

        var restored = 0
        var drawerRestored = 0
        for paneId in paneIds {
            guard let pane = store.pane(paneId) else {
                paneCoordinatorLogger.warning("Skipping view restore for pane \(paneId) — not in store")
                RestoreTrace.log("restoreAllViews skip missing pane=\(paneId)")
                continue
            }
            RestoreTrace.log("restoreAllViews restoring pane=\(paneId) content=\(String(describing: pane.content))")
            if createViewForContent(pane: pane) != nil {
                restored += 1
            }

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
        paneCoordinatorLogger.info(
            "Restored \(restored)/\(paneIds.count) pane views, \(drawerRestored) drawer pane views")

        if let activeTab = store.activeTab,
            let activePaneId = activeTab.activePaneId,
            let terminalView = viewRegistry.terminalView(for: activePaneId)
        {
            surfaceManager.syncFocus(activeSurfaceId: terminalView.surfaceId)
            RestoreTrace.log(
                "restoreAllViews syncFocus activeTab=\(activeTab.id) activePane=\(activePaneId) activeSurface=\(terminalView.surfaceId?.uuidString ?? "nil")"
            )
        }
        RestoreTrace.log("restoreAllViews end restored=\(restored) drawerRestored=\(drawerRestored)")
    }

    private func buildZmxAttachCommand(pane: Pane, worktree: Worktree, repo: Repo, zmxPath: String) -> String {
        let zmxSessionName: String
        if let parentPaneId = pane.parentPaneId {
            zmxSessionName = ZmxBackend.drawerSessionId(parentPaneId: parentPaneId, drawerPaneId: pane.id)
        } else {
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
