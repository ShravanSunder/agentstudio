import AppKit
import Foundation
import GhosttyKit

@MainActor
extension PaneCoordinator {
    private struct RestoreAllViewsProgress {
        var restored = 0
        var drawerRestored = 0
        var failedPaneIds: [UUID] = []
        var failedDrawerPaneIds: [UUID] = []
        var restoredPaneIds: Set<UUID> = []
    }

    static func floatingZmxRestoreSessionId(for pane: Pane, workingDirectory: URL) -> String {
        if let parentPaneId = pane.parentPaneId {
            return ZmxBackend.drawerSessionId(
                parentPaneId: parentPaneId,
                drawerPaneId: pane.id
            )
        }

        return ZmxBackend.floatingSessionId(
            workingDirectory: workingDirectory,
            paneId: pane.id
        )
    }

    /// Create a view for any pane content type. Dispatches to the appropriate factory.
    /// Returns the created PaneView, or nil on failure.
    func createViewForContent(
        pane: Pane,
        initialFrame: NSRect? = nil,
        treatAsRestoredSessionStart: Bool = false
    ) -> PaneView? {
        switch pane.content {
        case .terminal:
            if let worktreeId = pane.worktreeId,
                let repoId = pane.repoId,
                let worktree = store.worktree(worktreeId),
                let repo = store.repo(repoId)
            {
                return createView(
                    for: pane,
                    worktree: worktree,
                    repo: repo,
                    initialFrame: initialFrame,
                    treatAsRestoredSessionStart: treatAsRestoredSessionStart
                )

            } else if let parentPaneId = pane.parentPaneId,
                let parentPane = store.pane(parentPaneId),
                let worktreeId = parentPane.worktreeId,
                let repoId = parentPane.repoId,
                let worktree = store.worktree(worktreeId),
                let repo = store.repo(repoId)
            {
                return createView(
                    for: pane,
                    worktree: worktree,
                    repo: repo,
                    initialFrame: initialFrame,
                    treatAsRestoredSessionStart: treatAsRestoredSessionStart
                )

            } else {
                return createFloatingTerminalView(
                    for: pane,
                    initialFrame: initialFrame,
                    treatAsRestoredSessionStart: treatAsRestoredSessionStart
                )
            }

        case .webview(let state):
            let view = WebviewPaneView(paneId: pane.id, state: state)
            let paneId = pane.id
            view.controller.onTitleChange = { [weak self] title in
                self?.store.updatePaneTitle(paneId, title: title)
            }
            viewRegistry.register(view, for: pane.id)
            registerRuntimeIfNeeded(runtime: view.runtime, for: pane)
            Self.logger.info("Created webview pane \(pane.id)")
            return view

        case .codeViewer(let state):
            let initialText: String?
            if let codeViewerRuntime = registerCodeViewerRuntimeIfNeeded(for: pane) {
                if codeViewerRuntime.lifecycle == .created {
                    let transitioned = codeViewerRuntime.transitionToReady()
                    if !transitioned {
                        Self.logger.warning(
                            "Code viewer runtime for pane \(pane.id.uuidString, privacy: .public) failed ready transition"
                        )
                    }
                }
                initialText = codeViewerRuntime.displayedText.isEmpty ? nil : codeViewerRuntime.displayedText
            } else {
                initialText = nil
            }

            let view = CodeViewerPaneView(
                paneId: pane.id,
                state: state,
                initialText: initialText
            )
            viewRegistry.register(view, for: pane.id)
            Self.logger.info("Created code viewer pane \(pane.id)")
            return view

        case .bridgePanel(let state):
            let controller = BridgePaneController(paneId: pane.id, state: state)
            let view = BridgePaneView(paneId: pane.id, controller: controller)
            viewRegistry.register(view, for: pane.id)
            registerRuntimeIfNeeded(runtime: view.runtime, for: pane)
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
        repo: Repo,
        initialFrame: NSRect? = nil,
        treatAsRestoredSessionStart: Bool = false
    ) -> AgentStudioTerminalView? {
        let workingDir = pane.metadata.facets.cwd ?? worktree.path

        let shellCommand = "\(getDefaultShell()) -i -l"
        let startupStrategy: Ghostty.SurfaceStartupStrategy
        let showsRestorePresentationDuringStartup: Bool
        var environmentVariables: [String: String] = [:]
        switch pane.provider {
        case .zmx:
            if let diagnostics = terminalRestoreRuntime.zmxAttachDiagnostics(for: pane, store: store) {
                RestoreTrace.log(
                    "createView zmxDiagnostics pane=\(diagnostics.paneId) session=\(diagnostics.sessionId) socketPathLen=\(diagnostics.socketPathLength) socketPathHeadroom=\(diagnostics.socketPathHeadroom) maxSocketPathLen=\(diagnostics.maxSocketPathLength)"
                )
            }
            if let attachCommand = terminalRestoreRuntime.zmxAttachCommand(for: pane, store: store) {
                startupStrategy = .surfaceCommand(attachCommand)
                showsRestorePresentationDuringStartup = treatAsRestoredSessionStart
                environmentVariables["ZMX_DIR"] = sessionConfig.zmxDir
            } else {
                Self.logger.error(
                    "zmx not found; using ephemeral session for \(pane.id) (state will not persist)"
                )
                if !pane.metadata.title.localizedCaseInsensitiveContains("ephemeral") {
                    store.updatePaneTitle(pane.id, title: "\(pane.metadata.title) [ephemeral]")
                }
                startupStrategy = .surfaceCommand(shellCommand)
                showsRestorePresentationDuringStartup = false
            }
        case .ghostty:
            startupStrategy = .surfaceCommand(shellCommand)
            showsRestorePresentationDuringStartup = false
        case .none:
            Self.logger.error("Cannot create view for non-terminal pane \(pane.id)")
            return nil
        }

        let config = Ghostty.SurfaceConfiguration(
            workingDirectory: workingDir.path,
            startupStrategy: startupStrategy,
            initialFrame: initialFrame,
            environmentVariables: environmentVariables
        )

        let metadata = SurfaceMetadata(
            workingDirectory: workingDir,
            command: startupStrategy.startupCommandForSurface,
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
                paneId: pane.id,
                showsRestorePresentationDuringStartup: showsRestorePresentationDuringStartup
            )
            view.onRepairRequested = { [weak self] paneId in
                self?.execute(.repair(.recreateSurface(paneId: paneId)))
            }
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
    private func createFloatingTerminalView(
        for pane: Pane,
        initialFrame: NSRect? = nil,
        treatAsRestoredSessionStart: Bool = false
    ) -> AgentStudioTerminalView? {
        let workingDir = pane.metadata.facets.cwd ?? FileManager.default.homeDirectoryForCurrentUser
        let shellCommand = "\(getDefaultShell()) -i -l"
        let startupStrategy: Ghostty.SurfaceStartupStrategy
        let showsRestorePresentationDuringStartup: Bool
        var environmentVariables: [String: String] = [:]

        if pane.provider == .zmx,
            let diagnostics = terminalRestoreRuntime.zmxAttachDiagnostics(for: pane, store: store)
        {
            RestoreTrace.log(
                "createFloatingView zmxDiagnostics pane=\(diagnostics.paneId) session=\(diagnostics.sessionId) socketPathLen=\(diagnostics.socketPathLength) socketPathHeadroom=\(diagnostics.socketPathHeadroom) maxSocketPathLen=\(diagnostics.maxSocketPathLength)"
            )
        }

        if pane.provider == .zmx,
            let attachCommand = terminalRestoreRuntime.zmxAttachCommand(for: pane, store: store)
        {
            startupStrategy = .surfaceCommand(attachCommand)
            showsRestorePresentationDuringStartup = treatAsRestoredSessionStart
            environmentVariables["ZMX_DIR"] = sessionConfig.zmxDir
            RestoreTrace.log(
                "createFloatingView zmx pane=\(pane.id) session=\(Self.floatingZmxRestoreSessionId(for: pane, workingDirectory: workingDir)) cwd=\(workingDir.path)"
            )
        } else {
            if pane.provider == .zmx {
                Self.logger.error(
                    "zmx not found; using ephemeral floating session for \(pane.id) (state will not persist)"
                )
                if !pane.metadata.title.localizedCaseInsensitiveContains("ephemeral") {
                    store.updatePaneTitle(pane.id, title: "\(pane.metadata.title) [ephemeral]")
                }
            }
            startupStrategy = .surfaceCommand(shellCommand)
            showsRestorePresentationDuringStartup = false
        }

        RestoreTrace.log(
            "createFloatingView pane=\(pane.id) cwd=\(workingDir.path) cmd=\(shellCommand)"
        )

        let config = Ghostty.SurfaceConfiguration(
            workingDirectory: workingDir.path,
            startupStrategy: startupStrategy,
            initialFrame: initialFrame,
            environmentVariables: environmentVariables
        )

        let metadata = SurfaceMetadata(
            workingDirectory: workingDir,
            command: startupStrategy.startupCommandForSurface,
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
                title: pane.metadata.title,
                showsRestorePresentationDuringStartup: showsRestorePresentationDuringStartup
            )
            view.onRepairRequested = { [weak self] paneId in
                self?.execute(.repair(.recreateSurface(paneId: paneId)))
            }
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
        guard let terminal = viewRegistry.terminalView(for: paneId) else {
            Self.logger.warning(
                "Unable to reattach pane \(paneId.uuidString, privacy: .public): terminal view not found"
            )
            return
        }
        guard let surfaceId = terminal.surfaceId else {
            Self.logger.warning(
                "Unable to reattach pane \(paneId.uuidString, privacy: .public): terminal view has no surface id"
            )
            return
        }
        guard let surfaceView = surfaceManager.attach(surfaceId, to: paneId) else {
            Self.logger.warning(
                "Unable to reattach pane \(paneId.uuidString, privacy: .public): attach returned nil for surface \(surfaceId.uuidString, privacy: .public)"
            )
            return
        }
        terminal.displaySurface(surfaceView)
        Self.logger.debug("Reattached pane \(paneId.uuidString, privacy: .public) for view switch")
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
        guard terminalRuntime.transitionToReady() else {
            Self.logger.warning(
                "Terminal runtime for pane \(pane.id.uuidString, privacy: .public) failed ready transition; skipping runtime registration"
            )
            return
        }
        registerRuntime(terminalRuntime)
    }

    private func registerCodeViewerRuntimeIfNeeded(for pane: Pane) -> SwiftPaneRuntime? {
        guard let runtimePaneId = runtimePaneId(for: pane.id) else {
            Self.logger.warning(
                "Skipping code viewer runtime registration for non-v7 pane id \(pane.id.uuidString, privacy: .public)"
            )
            return nil
        }
        let canonicalMetadata = pane.metadata.canonicalizedIdentity(
            paneId: runtimePaneId,
            contentType: .codeViewer
        )

        if let existing = runtimeForPane(runtimePaneId) as? SwiftPaneRuntime {
            if existing.lifecycle == .terminated {
                _ = unregisterRuntime(runtimePaneId)
            } else {
                return existing
            }
        }

        let runtime = SwiftPaneRuntime(
            paneId: runtimePaneId,
            metadata: canonicalMetadata
        )
        registerRuntime(runtime)
        return runtime
    }

    private func registerRuntimeIfNeeded(runtime: any PaneRuntime, for pane: Pane) {
        guard let runtimePaneId = runtimePaneId(for: pane.id) else { return }
        guard runtime.paneId == runtimePaneId else {
            Self.logger.error(
                "Runtime pane id mismatch during registration for pane \(pane.id.uuidString, privacy: .public)"
            )
            return
        }

        if let existing = runtimeForPane(runtimePaneId) {
            let existingId = ObjectIdentifier(existing as AnyObject)
            let incomingId = ObjectIdentifier(runtime as AnyObject)
            if existingId == incomingId {
                return
            }
            _ = unregisterRuntime(runtimePaneId)
        }
        registerRuntime(runtime)
    }

    private func runtimePaneId(for paneId: UUID) -> PaneId? {
        guard UUIDv7.isV7(paneId) else {
            Self.logger.error(
                "Runtime registration requested for non-v7 pane id \(paneId.uuidString, privacy: .public)"
            )
            return nil
        }
        return PaneId(uuid: paneId)
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
        let restoredView = createView(
            for: pane,
            worktree: worktree,
            repo: repo,
            treatAsRestoredSessionStart: true
        )
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
    func restoreAllViews(in terminalContainerBounds: CGRect? = nil) async {
        if let terminalContainerBounds {
            RestoreTrace.log(
                "restoreAllViews inputBounds=\(NSStringFromRect(terminalContainerBounds))"
            )
        } else {
            RestoreTrace.log("restoreAllViews inputBounds=nil")
        }
        let orderedPaneIds = TerminalRestoreScheduler.order(
            Self.orderedUniquePaneIds(store.tabs.flatMap(\.panes)).map(PaneId.init(uuid:)),
            resolver: visibilityTierResolver
        ).map(\.uuid)
        RestoreTrace.log(
            "restoreAllViews begin tabs=\(store.tabs.count) paneIds=\(orderedPaneIds.count) activeTab=\(store.activeTabId?.uuidString ?? "nil")"
        )
        guard !orderedPaneIds.isEmpty else {
            Self.logger.info("No panes to restore views for")
            RestoreTrace.log("restoreAllViews no panes")
            return
        }

        let visiblePaneIds = orderedPaneIds.filter {
            visibilityTierResolver.tier(for: PaneId(uuid: $0)) == .p0Visible
        }
        let hiddenPaneIds = orderedPaneIds.filter {
            visibilityTierResolver.tier(for: PaneId(uuid: $0)) == .p1Hidden
        }
        let liveHiddenSessionIds = await hiddenLiveSessionIds()
        let resolvedPaneFramesByTabId = resolveInitialFramesByTabId(in: terminalContainerBounds)
        var progress = RestoreAllViewsProgress()

        // Stage 1: restore currently visible panes first for fast first paint/interaction.
        for paneId in visiblePaneIds {
            restorePaneAndDrawers(
                paneId,
                resolvedPaneFramesByTabId: resolvedPaneFramesByTabId,
                liveHiddenSessionIds: liveHiddenSessionIds,
                progress: &progress
            )
        }
        if !visiblePaneIds.isEmpty {
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

        // Stage 2: restore eligible hidden panes cooperatively after visible work.
        for (index, paneId) in hiddenPaneIds.enumerated() {
            if Task.isCancelled { break }
            restorePaneAndDrawers(
                paneId,
                resolvedPaneFramesByTabId: resolvedPaneFramesByTabId,
                liveHiddenSessionIds: liveHiddenSessionIds,
                progress: &progress
            )
            if index.isMultiple(of: 2) {
                store.bumpViewRevision()
                await Task.yield()
            }
        }

        if !hiddenPaneIds.isEmpty {
            store.bumpViewRevision()
        }

        Self.logger.info(
            "Restored \(progress.restored)/\(orderedPaneIds.count) pane views, \(progress.drawerRestored) drawer pane views"
        )
        if !progress.failedPaneIds.isEmpty || !progress.failedDrawerPaneIds.isEmpty {
            let failedPrimary = progress.failedPaneIds.map(\.uuidString).joined(separator: ", ")
            let failedDrawer = progress.failedDrawerPaneIds.map(\.uuidString).joined(separator: ", ")
            Self.logger.error(
                """
                restoreAllViews: failed view creation primary=[\(failedPrimary)] drawer=[\(failedDrawer)] \
                (panes remain in store/layout and may appear as placeholders)
                """
            )
        }

        RestoreTrace.log("restoreAllViews end restored=\(progress.restored) drawerRestored=\(progress.drawerRestored)")
    }

    private static func orderedUniquePaneIds(_ paneIds: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return paneIds.filter { seen.insert($0).inserted }
    }

    private func hiddenLiveSessionIds() async -> Set<String> {
        let hiddenZmxPaneIds = store.panes.values.compactMap { pane -> UUID? in
            guard pane.provider == .zmx else { return nil }
            let paneId = PaneId(uuid: pane.id)
            return visibilityTierResolver.tier(for: paneId) == .p1Hidden ? pane.id : nil
        }
        let needsHiddenSessionDiscovery =
            sessionConfig.backgroundRestorePolicy != .off
            && !hiddenZmxPaneIds.isEmpty
        if !needsHiddenSessionDiscovery {
            return []
        }
        return await terminalRestoreRuntime.discoverLiveSessionIds()
    }

    private func shouldRestoreHiddenPane(
        _ pane: Pane,
        liveHiddenSessionIds: Set<String>
    ) -> Bool {
        let paneId = PaneId(uuid: pane.id)
        guard visibilityTierResolver.tier(for: paneId) == .p1Hidden else {
            return true
        }
        return terminalRestoreRuntime.shouldRestoreHiddenPane(
            pane,
            store: store,
            liveSessionIds: liveHiddenSessionIds
        )
    }

    private func initialFrame(
        for pane: Pane,
        resolvedPaneFramesByTabId: [UUID: [UUID: CGRect]]
    ) -> NSRect? {
        let owningPaneId = pane.parentPaneId ?? pane.id
        guard let tab = store.tabContaining(paneId: owningPaneId) else {
            return nil
        }
        guard let frame = resolvedPaneFramesByTabId[tab.id]?[pane.id], !frame.isEmpty else {
            return nil
        }
        return NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
    }

    private func restorePaneAndDrawers(
        _ paneId: UUID,
        resolvedPaneFramesByTabId: [UUID: [UUID: CGRect]],
        liveHiddenSessionIds: Set<String>,
        progress: inout RestoreAllViewsProgress
    ) {
        guard progress.restoredPaneIds.insert(paneId).inserted else { return }
        guard let pane = store.pane(paneId) else {
            Self.logger.warning("Skipping view restore for pane \(paneId) — not in store")
            RestoreTrace.log("restoreAllViews skip missing pane=\(paneId)")
            return
        }
        guard shouldRestoreHiddenPane(pane, liveHiddenSessionIds: liveHiddenSessionIds) else {
            RestoreTrace.log("restoreAllViews skip hidden pane=\(paneId) reason=policy")
            restoreDrawerPanes(
                for: pane,
                resolvedPaneFramesByTabId: resolvedPaneFramesByTabId,
                liveHiddenSessionIds: liveHiddenSessionIds,
                progress: &progress
            )
            return
        }

        RestoreTrace.log("restoreAllViews restoring pane=\(paneId) content=\(String(describing: pane.content))")
        if viewRegistry.view(for: paneId) != nil
            || createViewForContent(
                pane: pane,
                initialFrame: initialFrame(for: pane, resolvedPaneFramesByTabId: resolvedPaneFramesByTabId),
                treatAsRestoredSessionStart: true
            ) != nil
        {
            progress.restored += 1
        } else {
            progress.failedPaneIds.append(paneId)
        }

        restoreDrawerPanes(
            for: pane,
            resolvedPaneFramesByTabId: resolvedPaneFramesByTabId,
            liveHiddenSessionIds: liveHiddenSessionIds,
            progress: &progress
        )
    }

    func restoreViewsForActiveTabIfNeeded() {
        guard let activeTab = store.activeTab else { return }
        guard let terminalContainerBounds = terminalContainerBoundsProvider(), !terminalContainerBounds.isEmpty else {
            RestoreTrace.log("restoreViewsForActiveTabIfNeeded skipped boundsUnavailable")
            return
        }
        RestoreTrace.log(
            "restoreViewsForActiveTabIfNeeded activeTab=\(activeTab.id) bounds=\(NSStringFromRect(terminalContainerBounds))"
        )
        let resolvedPaneFramesByTabId = resolveInitialFramesByTabId(in: terminalContainerBounds)
        let visiblePaneIds = TerminalRestoreScheduler.order(
            store.panes.keys.map(PaneId.init(uuid:)),
            resolver: visibilityTierResolver
        )
        .filter { visibilityTierResolver.tier(for: $0) == .p0Visible }
        .map(\.uuid)

        var createdAnyViews = false
        for paneId in visiblePaneIds {
            guard let pane = store.pane(paneId) else { continue }
            guard store.tabContaining(paneId: pane.parentPaneId ?? pane.id)?.id == activeTab.id else {
                continue
            }
            guard viewRegistry.view(for: paneId) == nil else { continue }
            if createViewForContent(
                pane: pane,
                initialFrame: initialFrame(for: pane, resolvedPaneFramesByTabId: resolvedPaneFramesByTabId),
                treatAsRestoredSessionStart: true
            ) != nil {
                createdAnyViews = true
            }
        }

        if createdAnyViews {
            store.bumpViewRevision()
        }
    }

    private func restoreDrawerPanes(
        for parentPane: Pane,
        resolvedPaneFramesByTabId: [UUID: [UUID: CGRect]],
        liveHiddenSessionIds: Set<String>,
        progress: inout RestoreAllViewsProgress
    ) {
        guard let drawer = parentPane.drawer else { return }
        for drawerPaneId in drawer.paneIds {
            guard progress.restoredPaneIds.insert(drawerPaneId).inserted else { continue }
            guard let drawerPane = store.pane(drawerPaneId) else {
                Self.logger.warning(
                    "restoreAllViews: drawer pane \(drawerPaneId) referenced by parent \(parentPane.id) is missing from store"
                )
                continue
            }
            guard shouldRestoreHiddenPane(drawerPane, liveHiddenSessionIds: liveHiddenSessionIds) else {
                RestoreTrace.log(
                    "restoreAllViews skip hidden drawer pane=\(drawerPaneId) parent=\(parentPane.id) reason=policy"
                )
                continue
            }
            RestoreTrace.log("restoreAllViews restoring drawer pane=\(drawerPaneId) parent=\(parentPane.id)")
            if viewRegistry.view(for: drawerPaneId) != nil
                || createViewForContent(
                    pane: drawerPane,
                    initialFrame: initialFrame(
                        for: drawerPane,
                        resolvedPaneFramesByTabId: resolvedPaneFramesByTabId
                    ),
                    treatAsRestoredSessionStart: true
                ) != nil
            {
                progress.drawerRestored += 1
            } else {
                progress.failedDrawerPaneIds.append(drawerPaneId)
            }
        }
    }

    private func resolveInitialFramesByTabId(in terminalContainerBounds: CGRect?) -> [UUID: [UUID: CGRect]] {
        guard let terminalContainerBounds else {
            Self.logger.warning("resolveInitialFramesByTabId: terminal container bounds unavailable")
            RestoreTrace.log("resolveInitialFramesByTabId unavailableBounds")
            return [:]
        }
        guard !terminalContainerBounds.isEmpty else {
            Self.logger.warning("resolveInitialFramesByTabId: terminal container bounds empty")
            RestoreTrace.log("resolveInitialFramesByTabId emptyBounds")
            return [:]
        }

        return store.tabs.reduce(into: [UUID: [UUID: CGRect]]()) { result, tab in
            var resolvedFrames = TerminalPaneGeometryResolver.resolveFrames(
                for: tab.layout,
                in: terminalContainerBounds,
                dividerThickness: AppStyle.paneGap,
                minimizedPaneIds: tab.minimizedPaneIds
            )
            if resolvedFrames.isEmpty, !tab.layout.isEmpty {
                Self.logger.warning(
                    "resolveInitialFramesByTabId: no resolved frames for non-empty tab \(tab.id.uuidString, privacy: .public)"
                )
                RestoreTrace.log("resolveInitialFramesByTabId noFrames tab=\(tab.id)")
            }

            for paneId in tab.paneIds {
                guard
                    let parentFrame = resolvedFrames[paneId],
                    let drawer = store.pane(paneId)?.drawer,
                    drawer.isExpanded,
                    let drawerContentRect = resolvedDrawerContentRect(
                        parentPaneFrame: parentFrame,
                        tabSize: terminalContainerBounds.size
                    )
                else {
                    if store.pane(paneId)?.drawer?.isExpanded == true {
                        Self.logger.warning(
                            "resolveInitialFramesByTabId: missing expanded drawer geometry for parent pane \(paneId.uuidString, privacy: .public)"
                        )
                        RestoreTrace.log("resolveInitialFramesByTabId missingDrawerGeometry parent=\(paneId)")
                    }
                    continue
                }
                let drawerFrames = TerminalPaneGeometryResolver.resolveFrames(
                    for: drawer.layout,
                    in: drawerContentRect,
                    dividerThickness: AppStyle.paneGap,
                    minimizedPaneIds: drawer.minimizedPaneIds
                )

                for (drawerPaneId, drawerPaneFrame) in drawerFrames {
                    resolvedFrames[drawerPaneId] = drawerPaneFrame
                }
            }

            result[tab.id] = resolvedFrames
        }
    }

    private func resolvedDrawerContentRect(
        parentPaneFrame: CGRect,
        tabSize: CGSize
    ) -> CGRect? {
        guard tabSize.width > 0, tabSize.height > 0 else { return nil }

        let heightRatio = drawerHeightRatio()
        let panelWidth = tabSize.width * DrawerLayout.panelWidthRatio
        let panelHeight = max(
            DrawerLayout.panelMinHeight,
            min(tabSize.height * CGFloat(heightRatio), tabSize.height - DrawerLayout.panelBottomMargin)
        )
        let totalHeight = panelHeight + DrawerLayout.overlayConnectorHeight
        let overlayBottomY = parentPaneFrame.maxY - DrawerLayout.iconBarFrameHeight
        let centerY = overlayBottomY - totalHeight / 2
        let halfPanel = panelWidth / 2
        let edgeMargin = DrawerLayout.tabEdgeMargin
        let centerX = max(
            halfPanel + edgeMargin,
            min(tabSize.width - halfPanel - edgeMargin, parentPaneFrame.midX)
        )
        let panelLeft = centerX - halfPanel
        let panelTop = centerY - totalHeight / 2

        let contentRect = CGRect(
            x: panelLeft + DrawerLayout.panelContentPadding,
            y: panelTop + DrawerLayout.resizeHandleHeight,
            width: max(panelWidth - (DrawerLayout.panelContentPadding * 2), 1),
            height: max(
                panelHeight - DrawerLayout.resizeHandleHeight - DrawerLayout.panelContentPadding,
                1
            )
        )
        return contentRect.isEmpty ? nil : contentRect
    }

    private func drawerHeightRatio() -> Double {
        let storedValue = UserDefaults.standard.object(forKey: "drawerHeightRatio") as? Double
        return storedValue ?? DrawerLayout.heightRatioMax
    }

    private func getDefaultShell() -> String {
        SessionConfiguration.defaultShell()
    }
}
