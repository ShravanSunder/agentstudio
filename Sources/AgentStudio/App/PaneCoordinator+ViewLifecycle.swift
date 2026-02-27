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
            Self.logger.info("Created webview pane \(pane.id)")
            return view

        case .codeViewer(let state):
            let view = CodeViewerPaneView(paneId: pane.id, state: state)
            viewRegistry.register(view, for: pane.id)
            Self.logger.info("Created code viewer stub for pane \(pane.id)")
            return view

        case .bridgePanel(let state):
            let controller = BridgePaneController(paneId: pane.id, state: state)
            let view = BridgePaneView(paneId: pane.id, controller: controller)
            viewRegistry.register(view, for: pane.id)
            controller.loadApp()
            Self.logger.info("Created bridge panel view for pane \(pane.id)")
            return view

        case .unsupported:
            Self.logger.warning("Cannot create view for unsupported content type — pane \(pane.id)")
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
                Self.logger.error(
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
            Self.logger.error("Cannot create view for non-terminal pane \(pane.id)")
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
            contextFacets: pane.metadata.facets,
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
            registerTerminalRuntimeIfNeeded(for: pane)
            runtime.markRunning(pane.id)
            RestoreTrace.log(
                "createView complete pane=\(pane.id) surface=\(managed.id) viewBounds=\(NSStringFromRect(view.bounds))"
            )

            Self.logger.info("Created view for pane \(pane.id) worktree: \(worktree.name)")
            return view

        case .failure(let error):
            RestoreTrace.log(
                "createSurface failure pane=\(pane.id) error=\(error.localizedDescription)"
            )
            Self.logger.error("Failed to create surface for pane \(pane.id): \(error.localizedDescription)")
            return nil
        }
    }

    /// Create a terminal view for a floating pane (drawers, standalone terminals).
    /// No worktree/repo context — uses home directory or pane's cwd.
    @discardableResult
    private func createFloatingTerminalView(for pane: Pane) -> AgentStudioTerminalView? {
        let workingDir = pane.metadata.facets.cwd ?? FileManager.default.homeDirectoryForCurrentUser
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
            contextFacets: pane.metadata.facets,
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
            registerTerminalRuntimeIfNeeded(for: pane)
            runtime.markRunning(pane.id)
            RestoreTrace.log("createFloatingView complete pane=\(pane.id) surface=\(managed.id)")

            Self.logger.info("Created floating terminal view for pane \(pane.id)")
            return view

        case .failure(let error):
            RestoreTrace.log(
                "createFloatingSurface failure pane=\(pane.id) error=\(error.localizedDescription)"
            )
            Self.logger.error(
                "Failed to create floating surface for pane \(pane.id): \(error.localizedDescription)")
            return nil
        }
    }

    /// Teardown a view — detach terminal surface, teardown bridge controller, unregister view/runtime state.
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
            if UUIDv7.isV7(paneId) {
                _ = unregisterRuntime(PaneId(uuid: paneId))
            } else {
                Self.logger.warning(
                    "Skipping runtime unregister for non-v7 pane id \(paneId.uuidString, privacy: .public)"
                )
            }
            runtime.removeSession(paneId)
        }

        Self.logger.debug("Tore down view for pane \(paneId)")
    }

    /// Detach a pane's surface for a view switch (hide, not destroy).
    func detachForViewSwitch(paneId: UUID) {
        if let terminal = viewRegistry.terminalView(for: paneId),
            let surfaceId = terminal.surfaceId
        {
            surfaceManager.detach(surfaceId, reason: .hide)
        }
        Self.logger.debug("Detached pane \(paneId) for view switch")
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
        Self.logger.debug("Reattached pane \(paneId) for view switch")
    }

    private func registerTerminalRuntimeIfNeeded(for pane: Pane) {
        guard case .terminal = pane.content else {
            Self.logger.debug(
                "Skipping terminal runtime registration for non-terminal pane \(pane.id.uuidString, privacy: .public)"
            )
            return
        }

        guard UUIDv7.isV7(pane.id) else {
            Self.logger.error(
                "Skipping terminal runtime registration for non-v7 pane id \(pane.id.uuidString, privacy: .public)"
            )
            return
        }
        let runtimePaneId = PaneId(uuid: pane.id)
        guard runtimeForPane(runtimePaneId) == nil else { return }

        let terminalRuntime = TerminalRuntime(
            paneId: runtimePaneId,
            metadata: pane.metadata
        )
        terminalRuntime.transitionToReady()
        guard terminalRuntime.lifecycle == .ready else {
            Self.logger.warning(
                "Terminal runtime for pane \(pane.id.uuidString, privacy: .public) failed ready transition; skipping runtime registration"
            )
            return
        }
        registerRuntime(terminalRuntime)
    }

    /// Restore a view from an undo close. Tries to reuse the undone surface; creates fresh if expired.
    @discardableResult
    func restoreView(
        for pane: Pane,
        worktree: Worktree,
        repo: Repo
    ) -> AgentStudioTerminalView? {
        guard UUIDv7.isV7(pane.id) else {
            Self.logger.error(
                "Unable to restore runtime for non-v7 pane id \(pane.id.uuidString, privacy: .public)"
            )
            return nil
        }
        let runtimePaneId = PaneId(uuid: pane.id)
        let runtimeWasAlreadyRegistered = runtimeForPane(runtimePaneId) != nil
        if !runtimeWasAlreadyRegistered {
            registerTerminalRuntimeIfNeeded(for: pane)
        }

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
                Self.logger.info("Restored view from undo for pane \(pane.id)")
                return view
            } else {
                Self.logger.warning(
                    "Undo surface metadata mismatch: expected pane \(pane.id), got \(undone.metadata.paneId?.uuidString ?? "nil") — creating fresh"
                )
                surfaceManager.requeueUndo(undone.id)
            }
        }

        Self.logger.info("Creating fresh view for pane \(pane.id)")
        let restoredView = createView(for: pane, worktree: worktree, repo: repo)
        if restoredView == nil, !runtimeWasAlreadyRegistered {
            _ = unregisterRuntime(runtimePaneId)
        }
        return restoredView
    }

    /// Recreate views for all restored panes in all tabs, including drawer panes.
    /// Called once at launch after store.restore() populates persisted state.
    ///
    /// Startup is staged so the active tab is restored first, then background tabs
    /// are hydrated cooperatively with yields to keep first-interaction latency low.
    func restoreAllViews() async {
        let orderedPaneIds = Self.orderedUniquePaneIds(store.tabs.flatMap(\.panes))
        RestoreTrace.log(
            "restoreAllViews begin tabs=\(store.tabs.count) paneIds=\(orderedPaneIds.count) activeTab=\(store.activeTabId?.uuidString ?? "nil")"
        )
        guard !orderedPaneIds.isEmpty else {
            Self.logger.info("No panes to restore views for")
            RestoreTrace.log("restoreAllViews no panes")
            return
        }

        let activeTabPaneIds = Self.orderedUniquePaneIds(store.activeTab?.panes ?? [])
        let activeTabPaneIdSet = Set(activeTabPaneIds)
        let deferredPaneIds = orderedPaneIds.filter { !activeTabPaneIdSet.contains($0) }

        var restored = 0
        var drawerRestored = 0
        var failedPaneIds: [UUID] = []
        var failedDrawerPaneIds: [UUID] = []
        var restoredPaneIds: Set<UUID> = []

        func restorePaneAndDrawers(_ paneId: UUID) {
            guard restoredPaneIds.insert(paneId).inserted else { return }
            guard let pane = store.pane(paneId) else {
                Self.logger.warning("Skipping view restore for pane \(paneId) — not in store")
                RestoreTrace.log("restoreAllViews skip missing pane=\(paneId)")
                return
            }

            RestoreTrace.log("restoreAllViews restoring pane=\(paneId) content=\(String(describing: pane.content))")
            if viewRegistry.view(for: paneId) != nil || createViewForContent(pane: pane) != nil {
                restored += 1
            } else {
                failedPaneIds.append(paneId)
            }

            guard let drawer = pane.drawer else { return }
            for drawerPaneId in drawer.paneIds {
                guard restoredPaneIds.insert(drawerPaneId).inserted else { continue }
                guard let drawerPane = store.pane(drawerPaneId) else {
                    Self.logger.warning(
                        "restoreAllViews: drawer pane \(drawerPaneId) referenced by parent \(pane.id) is missing from store"
                    )
                    continue
                }
                RestoreTrace.log("restoreAllViews restoring drawer pane=\(drawerPaneId) parent=\(pane.id)")
                if viewRegistry.view(for: drawerPaneId) != nil || createViewForContent(pane: drawerPane) != nil {
                    drawerRestored += 1
                } else {
                    failedDrawerPaneIds.append(drawerPaneId)
                }
            }
        }

        // Stage 1: restore active tab first for fast first paint/interaction.
        for paneId in activeTabPaneIds {
            restorePaneAndDrawers(paneId)
        }
        if !activeTabPaneIds.isEmpty {
            store.bumpViewRevision()
        }

        if let activeTab = store.activeTab,
            let activePaneId = activeTab.activePaneId,
            let terminalView = viewRegistry.terminalView(for: activePaneId)
        {
            surfaceManager.syncFocus(activeSurfaceId: terminalView.surfaceId)
            RestoreTrace.log(
                "restoreAllViews syncFocus activeTab=\(activeTab.id) activePane=\(activePaneId) activeSurface=\(terminalView.surfaceId?.uuidString ?? "nil")"
            )
        }

        // Stage 2: restore remaining tabs in cooperative chunks.
        for (index, paneId) in deferredPaneIds.enumerated() {
            if Task.isCancelled { break }
            restorePaneAndDrawers(paneId)
            if index.isMultiple(of: 2) {
                store.bumpViewRevision()
                await Task.yield()
            }
        }

        if !deferredPaneIds.isEmpty {
            store.bumpViewRevision()
        }

        Self.logger.info(
            "Restored \(restored)/\(orderedPaneIds.count) pane views, \(drawerRestored) drawer pane views")
        if !failedPaneIds.isEmpty || !failedDrawerPaneIds.isEmpty {
            let failedPrimary = failedPaneIds.map(\.uuidString).joined(separator: ", ")
            let failedDrawer = failedDrawerPaneIds.map(\.uuidString).joined(separator: ", ")
            Self.logger.error(
                """
                restoreAllViews: failed view creation primary=[\(failedPrimary)] drawer=[\(failedDrawer)] \
                (panes remain in store/layout and may appear as placeholders)
                """
            )
        }

        RestoreTrace.log("restoreAllViews end restored=\(restored) drawerRestored=\(drawerRestored)")
    }

    private static func orderedUniquePaneIds(_ paneIds: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return paneIds.filter { seen.insert($0).inserted }
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
