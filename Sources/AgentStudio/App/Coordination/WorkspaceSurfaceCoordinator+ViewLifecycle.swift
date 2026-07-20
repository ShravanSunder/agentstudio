import AppKit
import Foundation
import GhosttyKit

@MainActor
extension WorkspaceSurfaceCoordinator {
    enum ViewTeardownReplayEvictionPolicy {
        case schedule
        case callerManaged
    }

    private struct TerminalSurfaceStartupPreparation {
        let strategy: Ghostty.SurfaceStartupStrategy
        let showsRestorePresentationDuringStartup: Bool
        let environmentVariables: [String: String]
    }

    private enum TerminalSurfaceStartupContext {
        case worktree
        case floating(launchDirectory: URL)

        var diagnosticsTracePrefix: String {
            switch self {
            case .worktree:
                "createView"
            case .floating:
                "createFloatingView"
            }
        }

        var missingZmxLogMessage: String {
            switch self {
            case .worktree:
                "zmx not found; using ephemeral session"
            case .floating:
                "zmx not found; using ephemeral floating session"
            }
        }
    }
    @discardableResult
    func registerHostedView(
        mountedView: NSView & PaneMountedContent,
        for paneId: UUID
    ) -> PaneHostView {
        let host = PaneHostView(paneId: paneId)
        host.onAttachedToWindow = { [weak self] attachedPaneId in
            self?.handlePaneHostAttachedToWindow(attachedPaneId)
        }
        host.mountContentView(mountedView)
        viewRegistry.register(host, for: paneId)
        return host
    }

    /// Create a view for any pane content type. Dispatches to the appropriate factory.
    /// Returns the created mounted content view, or nil on failure.
    func createViewForContent(
        pane: Pane,
        initialFrame: NSRect? = nil,
        treatAsRestoredSessionStart: Bool = false
    ) -> NSView? {
        if case .bridgePanel = pane.content,
            bridgePaneRetirementTasksByPaneId[pane.id] != nil
        {
            bridgePaneRetirementsRequiringRestore.insert(pane.id)
            return viewRegistry.view(for: pane.id)?.mountedContent(as: BridgePaneMountView.self)
        }
        let runtimePaneID = PaneId(existingUUID: pane.id)
        if viewRegistry.isInitialRestorePending,
            preparedContentVisibilitySignalHandler([runtimePaneID]).contains(runtimePaneID)
        {
            RestoreTrace.log("createViewForContent signalledPreparedOwner pane=\(pane.id)")
            return nil
        }
        switch pane.content {
        case .terminal:
            return mountCurrentTerminalContent(
                pane: pane,
                initialFrame: initialFrame,
                treatAsRestoredSessionStart: treatAsRestoredSessionStart
            )

        case .bridgePanel(let state):
            return createBridgePaneView(for: pane, state: state)

        case .webview, .codeViewer, .unsupported:
            return mountCurrentNonterminalContent(pane: pane)
        }
    }

    @discardableResult
    func createView(
        for pane: Pane,
        worktree: Worktree,
        repo: Repo,
        initialFrame: NSRect? = nil,
        treatAsRestoredSessionStart: Bool = false
    ) -> TerminalPaneMountView? {
        if pane.provider == .zmx, initialFrame == nil {
            RestoreTrace.log(
                "createView deferred pane=\(pane.id) reason=missingInitialFrame"
            )
            Self.logger.warning(
                "Deferring zmx pane \(pane.id, privacy: .public) until trusted initialFrame exists"
            )
            registerTerminalPlaceholderIfNeeded(for: pane, mode: .preparing)
            return nil
        }
        let launchDirectory = pane.metadata.cwd ?? pane.metadata.launchDirectory ?? worktree.path

        let shellCommand = "\(getDefaultShell()) -i -l"
        guard
            let startupPreparation = prepareTerminalSurfaceStartup(
                for: pane,
                shellCommand: shellCommand,
                treatAsRestoredSessionStart: treatAsRestoredSessionStart,
                context: .worktree
            )
        else { return nil }

        let config = Ghostty.SurfaceConfiguration(
            launchDirectory: launchDirectory.path,
            startupStrategy: startupPreparation.strategy,
            initialFrame: initialFrame,
            environmentVariables: startupPreparation.environmentVariables
        )

        let metadata = SurfaceMetadata(
            launchDirectory: launchDirectory,
            command: startupPreparation.strategy.startupCommandForSurface,
            title: worktree.name,
            worktreeId: worktree.id,
            repoId: repo.id,
            contextFacets: pane.metadata.facets,
            paneId: pane.id
        )

        let preparedRuntime = prepareTerminalRuntimeForFreshSurfaceIfNeeded(for: pane)
        traceSurfaceCreateStarted(
            pane: pane,
            initialFrame: config.initialFrame,
            startupCommandPresent: startupPreparation.strategy.startupCommandForSurface != nil,
            environmentVariableCount: startupPreparation.environmentVariables.count
        )
        let result = surfaceManager.createSurface(config: config, metadata: metadata)

        switch result {
        case .success(let managed):
            traceSurfaceCreateSucceeded(pane: pane, surfaceID: managed.id)
            viewRegistry.unregister(pane.id)
            RestoreTrace.log(
                "createView success pane=\(pane.id) surface=\(managed.id) initialSurfaceFrame=\(NSStringFromRect(managed.surface.frame))"
            )
            surfaceManager.attach(managed.id, to: pane.id)
            traceSurfaceAttached(pane: pane, surfaceID: managed.id)

            let view = TerminalPaneMountView(
                worktree: worktree,
                repo: repo,
                restoredSurfaceId: managed.id,
                paneId: pane.id,
                showsRestorePresentationDuringStartup: startupPreparation.showsRestorePresentationDuringStartup,
                performanceTraceRecorder: performanceTraceRecorder
            )
            view.onRepairRequested = { [weak self] paneId in
                self?.execute(.repair(.recreateSurface(paneId: paneId)))
            }
            view.displaySurface(managed.surface)
            if let runtime = preparedRuntime?.runtime {
                view.bind(runtime: runtime)
            }

            registerHostedView(mountedView: view, for: pane.id)
            traceSurfaceDisplayed(pane: pane, surfaceID: managed.id)
            runtime.markRunning(pane.id)
            RestoreTrace.log(
                "createView complete pane=\(pane.id) surface=\(managed.id) viewBounds=\(NSStringFromRect(view.bounds))"
            )

            Self.logger.info("Created view for pane \(pane.id) worktree: \(worktree.name)")
            return view

        case .failure(let error):
            traceSurfaceCreateFailed(
                pane: pane,
                error: error,
                initialFrame: config.initialFrame,
                startupCommandPresent: startupPreparation.strategy.startupCommandForSurface != nil,
                environmentVariableCount: startupPreparation.environmentVariables.count
            )
            RestoreTrace.log(
                "createSurface failure pane=\(pane.id) error=\(error.localizedDescription)"
            )
            Self.logger.error("Failed to create surface for pane \(pane.id): \(error.localizedDescription)")
            rollbackPreparedTerminalRuntimeIfNeeded(preparedRuntime)
            registerTerminalPlaceholderIfNeeded(for: pane, mode: .failedToStart)
            return nil
        }
    }

    @discardableResult
    func createTopologyIndependentTerminalView(
        for pane: Pane,
        initialFrame: NSRect? = nil,
        treatAsRestoredSessionStart: Bool = false
    ) -> TopologyIndependentTerminalMountResult {
        if pane.provider == .zmx, initialFrame == nil {
            RestoreTrace.log(
                "createFloatingTerminalView deferred pane=\(pane.id) reason=missingInitialFrame"
            )
            Self.logger.warning(
                "Deferring floating zmx pane \(pane.id, privacy: .public) until trusted initialFrame exists"
            )
            registerTerminalPlaceholderIfNeeded(for: pane, mode: .preparing)
            return .failed(.trustedInitialFrameUnavailable)
        }
        let launchDirectory =
            pane.metadata.cwd ?? pane.metadata.launchDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        let shellCommand = "\(getDefaultShell()) -i -l"
        guard
            let startupPreparation = prepareTerminalSurfaceStartup(
                for: pane,
                shellCommand: shellCommand,
                treatAsRestoredSessionStart: treatAsRestoredSessionStart,
                context: .floating(launchDirectory: launchDirectory)
            )
        else { return .failed(.startupPreparationFailed) }

        RestoreTrace.log(
            "createFloatingView pane=\(pane.id) cwd=\(launchDirectory.path) cmd=\(shellCommand)"
        )

        let config = Ghostty.SurfaceConfiguration(
            launchDirectory: launchDirectory.path,
            startupStrategy: startupPreparation.strategy,
            initialFrame: initialFrame,
            environmentVariables: startupPreparation.environmentVariables
        )

        let metadata = SurfaceMetadata(
            launchDirectory: launchDirectory,
            command: startupPreparation.strategy.startupCommandForSurface,
            title: pane.metadata.title,
            contextFacets: pane.metadata.facets,
            paneId: pane.id
        )

        let preparedRuntime = prepareTerminalRuntimeForFreshSurfaceIfNeeded(for: pane)
        traceSurfaceCreateStarted(
            pane: pane,
            initialFrame: config.initialFrame,
            startupCommandPresent: startupPreparation.strategy.startupCommandForSurface != nil,
            environmentVariableCount: startupPreparation.environmentVariables.count
        )
        let result = surfaceManager.createSurface(config: config, metadata: metadata)

        switch result {
        case .success(let managed):
            traceSurfaceCreateSucceeded(pane: pane, surfaceID: managed.id)
            viewRegistry.unregister(pane.id)
            RestoreTrace.log(
                "createFloatingSurface success pane=\(pane.id) surface=\(managed.id) initialSurfaceFrame=\(NSStringFromRect(managed.surface.frame))"
            )
            guard
                let attachedSurface = attachTopologyIndependentSurface(
                    surfaceID: managed.id,
                    to: pane,
                    preparedRuntime: preparedRuntime
                )
            else {
                return .failed(.surfaceAttachmentFailed)
            }

            let view = TerminalPaneMountView(
                restoredSurfaceId: managed.id,
                paneId: pane.id,
                title: pane.metadata.title,
                showsRestorePresentationDuringStartup: startupPreparation.showsRestorePresentationDuringStartup,
                performanceTraceRecorder: performanceTraceRecorder
            )
            view.onRepairRequested = { [weak self] paneId in
                self?.execute(.repair(.recreateSurface(paneId: paneId)))
            }
            view.displaySurface(attachedSurface)
            if let runtime = preparedRuntime?.runtime {
                view.bind(runtime: runtime)
            }

            registerHostedView(mountedView: view, for: pane.id)
            traceSurfaceDisplayed(pane: pane, surfaceID: managed.id)
            runtime.markRunning(pane.id)
            RestoreTrace.log("createFloatingView complete pane=\(pane.id) surface=\(managed.id)")

            Self.logger.info("Created floating terminal view for pane \(pane.id)")
            return .mounted(MountedTerminalContent(view: view, surfaceID: managed.id))

        case .failure(let error):
            traceSurfaceCreateFailed(
                pane: pane,
                error: error,
                initialFrame: config.initialFrame,
                startupCommandPresent: startupPreparation.strategy.startupCommandForSurface != nil,
                environmentVariableCount: startupPreparation.environmentVariables.count
            )
            RestoreTrace.log(
                "createFloatingSurface failure pane=\(pane.id) error=\(error.localizedDescription)"
            )
            Self.logger.error(
                "Failed to create floating surface for pane \(pane.id): \(error.localizedDescription)")
            rollbackPreparedTerminalRuntimeIfNeeded(preparedRuntime)
            registerTerminalPlaceholderIfNeeded(for: pane, mode: .failedToStart)
            return .failed(.surfaceCreationFailed)
        }
    }

    private func attachTopologyIndependentSurface(
        surfaceID: UUID,
        to pane: Pane,
        preparedRuntime: (runtime: TerminalRuntime, wasCreated: Bool)?
    ) -> Ghostty.SurfaceView? {
        guard let attachedSurface = surfaceManager.attach(surfaceID, to: pane.id) else {
            RestoreTrace.log(
                "createFloatingSurface attachFailure pane=\(pane.id) surface=\(surfaceID)"
            )
            Self.logger.error(
                "Failed to attach floating terminal surface \(surfaceID) to pane \(pane.id)"
            )
            rollbackPreparedTerminalRuntimeIfNeeded(preparedRuntime)
            surfaceManager.destroy(surfaceID)
            registerTerminalPlaceholderIfNeeded(for: pane, mode: .failedToStart)
            return nil
        }
        traceSurfaceAttached(pane: pane, surfaceID: surfaceID)
        return attachedSurface
    }

    private func prepareTerminalSurfaceStartup(
        for pane: Pane,
        shellCommand: String,
        treatAsRestoredSessionStart: Bool,
        context: TerminalSurfaceStartupContext
    ) -> TerminalSurfaceStartupPreparation? {
        switch pane.provider {
        case .zmx:
            let diagnostics = terminalRestoreRuntime.zmxAttachDiagnostics(for: pane)
            if let diagnostics {
                RestoreTrace.log(
                    "\(context.diagnosticsTracePrefix) zmxDiagnostics pane=\(diagnostics.paneId) session=\(diagnostics.sessionId) socketPathLen=\(diagnostics.socketPathLength) socketPathHeadroom=\(diagnostics.socketPathHeadroom) maxSocketPathLen=\(diagnostics.maxSocketPathLength)"
                )
            }
            if let attachCommand = terminalRestoreRuntime.zmxAttachCommand(for: pane) {
                traceZmxAttachPrepared(pane: pane, diagnostics: diagnostics)
                // Prevent nested Agent Studio launches from inheriting an outer zmx session.
                let environmentVariables: [String: String] = [
                    "ZMX_DIR": sessionConfig.zmxDir,
                    "ZMX_SESSION": "",
                    "ZMX_SESSION_PREFIX": "",
                ]
                return TerminalSurfaceStartupPreparation(
                    strategy: .surfaceCommand(attachCommand),
                    showsRestorePresentationDuringStartup: treatAsRestoredSessionStart,
                    environmentVariables: environmentVariables
                )
            }

            traceZmxAttachFailed(pane: pane)
            Self.logger.error(
                "\(context.missingZmxLogMessage) for \(pane.id) (state will not persist)"
            )
            if treatAsRestoredSessionStart {
                // Initial restore activates the exact durable session or presents failure.
                // It must not rewrite composition or silently launch a replacement shell.
                registerTerminalPlaceholderIfNeeded(for: pane, mode: .failedToStart)
                return nil
            }
            if !pane.metadata.title.localizedCaseInsensitiveContains("ephemeral") {
                store.paneAtom.updatePaneTitle(pane.id, title: "\(pane.metadata.title) [ephemeral]")
            }
            return TerminalSurfaceStartupPreparation(
                strategy: .surfaceCommand(shellCommand),
                showsRestorePresentationDuringStartup: false,
                environmentVariables: [:]
            )

        case .ghostty:
            return TerminalSurfaceStartupPreparation(
                strategy: .surfaceCommand(shellCommand),
                showsRestorePresentationDuringStartup: false,
                environmentVariables: [:]
            )

        case .none:
            Self.logger.error("Cannot create view for non-terminal pane \(pane.id)")
            return nil
        }
    }

    /// Teardown a view — detach terminal surface, teardown bridge controller, unregister view/runtime state.
    func teardownView(for paneId: UUID, shouldUnregisterRuntime: Bool = true) {
        if shouldUnregisterRuntime {
            closeBridgePaneActivityAuthority(for: paneId)
        }
        removePaneFilesystemProjectionContext(paneId: paneId)
        if bridgePaneRetirementTasksByPaneId[paneId] != nil {
            recordBridgePaneRetirementDisposition(
                paneId: paneId,
                shouldUnregisterRuntime: shouldUnregisterRuntime
            )
            return
        }
        if let terminal = viewRegistry.terminalView(for: paneId),
            let surfaceId = terminal.surfaceId
        {
            surfaceManager.detach(surfaceId, reason: .close)
        }

        if let bridgeView = viewRegistry.view(for: paneId)?.mountedContent(as: BridgePaneMountView.self) {
            startTrackedBridgePaneRetirement(
                paneId: paneId,
                controller: bridgeView.controller,
                shouldUnregisterRuntime: shouldUnregisterRuntime
            )
            return
        }

        finishViewTeardown(paneId: paneId, shouldUnregisterRuntime: shouldUnregisterRuntime)
    }

    func finishViewTeardown(
        paneId: UUID,
        shouldUnregisterRuntime: Bool,
        retiringBridgeController: BridgePaneController? = nil,
        replayEvictionPolicy: ViewTeardownReplayEvictionPolicy = .schedule
    ) {
        if let retiringBridgeController,
            let currentController = viewRegistry.view(for: paneId)?.mountedContent(as: BridgePaneMountView.self)?
                .controller,
            currentController !== retiringBridgeController
        {
            Self.logger.error(
                "Preserving replacement bridge view while retiring prior controller for pane \(paneId)"
            )
        } else {
            viewRegistry.unregister(paneId)
        }
        refreshBridgePaneActivities()

        if shouldUnregisterRuntime {
            let runtimePaneId = PaneId(existingUUID: paneId)
            _ = unregisterRuntime(runtimePaneId)
            if case .schedule = replayEvictionPolicy {
                Task { [paneEventBus] in
                    await paneEventBus.evictReplay(sourceKey: EventSource.pane(runtimePaneId).description)
                }
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
        restoreVisiblePaneIfNeeded(paneId, forceWhenBoundsExist: true)
        guard let terminal = viewRegistry.terminalView(for: paneId) else {
            if viewRegistry.view(for: paneId) != nil {
                Self.logger.debug(
                    "Skipped terminal reattach for pane \(paneId.uuidString, privacy: .public): restored view is not an attachable terminal host"
                )
                return
            }
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
        terminal.displaySurface(surfaceView, geometryVerificationReason: "reattachForViewSwitch")
        if let pane = store.paneAtom.pane(paneId) {
            registerTerminalRuntimeIfNeeded(for: pane)
        }
        Self.logger.debug("Reattached pane \(paneId.uuidString, privacy: .public) for view switch")
    }

    func registerCodeViewerRuntimeIfNeeded(for pane: Pane) -> SwiftPaneRuntime? {
        let runtimePaneId = runtimePaneId(for: pane.id)
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

    func registerRuntimeIfNeeded(runtime: any PaneRuntime, for pane: Pane) {
        let runtimePaneId = runtimePaneId(for: pane.id)
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

    private func runtimePaneId(for paneId: UUID) -> PaneId {
        PaneId(existingUUID: paneId)
    }

    func registerPaneFilesystemContextIfNeeded(for pane: Pane) {
        upsertPaneFilesystemProjectionContext(for: pane)
    }

    /// Restore a view from an undo close. Tries to reuse the undone surface; creates fresh if expired.
    @discardableResult
    func restoreView(
        for pane: Pane,
        worktree: Worktree,
        repo: Repo
    ) -> TerminalPaneMountView? {
        let runtimePaneId = PaneId(existingUUID: pane.id)
        let runtimeWasAlreadyRegistered = runtimeForPane(runtimePaneId) != nil
        if let undone = surfaceManager.undoClose() {
            if undone.metadata.paneId == pane.id {
                let view = TerminalPaneMountView(
                    worktree: worktree,
                    repo: repo,
                    restoredSurfaceId: undone.id,
                    paneId: pane.id,
                    performanceTraceRecorder: performanceTraceRecorder
                )
                surfaceManager.attach(undone.id, to: pane.id)
                view.displaySurface(undone.surface)
                registerHostedView(mountedView: view, for: pane.id)
                registerTerminalRuntimeIfNeeded(for: pane)
                runtime.markRunning(pane.id)
                registerPaneFilesystemContextIfNeeded(for: pane)
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
        let restoredView =
            createViewForContentUsingCurrentGeometry(
                pane: pane,
                treatAsRestoredSessionStart: true
            ) as? TerminalPaneMountView
        if restoredView == nil, !runtimeWasAlreadyRegistered {
            _ = unregisterRuntime(runtimePaneId)
        }
        return restoredView
    }

    func initialFrame(
        for pane: Pane,
        resolvedPaneFramesByTabId: [UUID: [UUID: CGRect]]
    ) -> NSRect? {
        let owningPaneId = pane.parentPaneId ?? pane.id
        guard let tab = store.tabLayoutAtom.tabContaining(paneId: owningPaneId) else {
            return nil
        }
        guard let frame = resolvedPaneFramesByTabId[tab.id]?[pane.id], !frame.isEmpty else {
            return nil
        }
        return NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
    }

    func resolveInitialFramesByTabId(in terminalContainerBounds: CGRect?) -> [UUID: [UUID: CGRect]] {
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

        return store.tabLayoutAtom.tabs.reduce(into: [UUID: [UUID: CGRect]]()) { result, tab in
            var resolvedFrames = TerminalPaneGeometryResolver.resolveFrames(
                for: tab.layout,
                in: terminalContainerBounds,
                dividerThickness: AppStyles.General.Layout.paneGap,
                minimizedPaneIds: tab.activeMinimizedPaneIds,
                collapsedPaneWidth: AppStyles.Shell.PaneChrome.collapsedBarWidth
            )
            if resolvedFrames.isEmpty, !tab.layout.isEmpty {
                Self.logger.warning(
                    "resolveInitialFramesByTabId: no resolved frames for non-empty tab \(tab.id.uuidString, privacy: .public)"
                )
                RestoreTrace.log("resolveInitialFramesByTabId noFrames tab=\(tab.id)")
            }

            for paneId in tab.activePaneIds {
                guard
                    let parentFrame = resolvedFrames[paneId],
                    let drawer = store.paneAtom.pane(paneId)?.drawer,
                    drawer.isExpanded,
                    let drawerView = arrangementView.drawerView(forParent: paneId),
                    let drawerContentRect = resolvedDrawerContentRect(
                        parentPaneFrame: parentFrame,
                        tabSize: terminalContainerBounds.size
                    )
                else {
                    if store.paneAtom.pane(paneId)?.drawer?.isExpanded == true {
                        Self.logger.warning(
                            "resolveInitialFramesByTabId: missing expanded drawer geometry for parent pane \(paneId.uuidString, privacy: .public)"
                        )
                        RestoreTrace.log("resolveInitialFramesByTabId missingDrawerGeometry parent=\(paneId)")
                    }
                    continue
                }
                let drawerFrames = TerminalPaneGeometryResolver.resolveFrames(
                    for: drawerView.layout,
                    in: drawerContentRect,
                    dividerThickness: AppStyles.General.Layout.paneGap,
                    minimizedPaneIds: drawerView.minimizedPaneIds,
                    collapsedPaneWidth: AppStyles.Shell.PaneChrome.collapsedBarWidth
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
