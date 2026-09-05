import AgentStudioBridge
import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTerminal
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
    ///
    /// The retired launch-window presentation flag is never consulted here:
    /// it is a read-only fact now (only `FlatPaneStripContent` still reads it,
    /// for placeholder selection), not a creation gate. A terminal pane's
    /// sole creation gate is its per-pane `TerminalSurfaceCreationAuthority`;
    /// a nonterminal pane's is whether the prepared nonterminal lane already
    /// handled it — that lane's custody semantics are unchanged by this
    /// cutover.
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
        let preparedHandledPaneIDs = preparedContentVisibilitySignalHandler(
            currentVisibleQueuedSet(includingAtLeast: runtimePaneID)
        )
        switch pane.content {
        case .terminal:
            guard let authority = terminalSurfaceCreationAuthority(for: pane) else {
                RestoreTrace.log("createViewForContent signalledPreparedOwner pane=\(pane.id)")
                return nil
            }
            return mountCurrentTerminalContent(
                pane: pane,
                initialFrame: initialFrame,
                treatAsRestoredSessionStart: treatAsRestoredSessionStart,
                authority: authority
            )

        case .webview, .codeViewer, .bridgePanel, .unsupported:
            guard !preparedHandledPaneIDs.contains(runtimePaneID) else {
                RestoreTrace.log("createViewForContent signalledPreparedOwner pane=\(pane.id)")
                return nil
            }
            return mountCurrentNonterminalContent(pane: pane)
        }
    }

    /// The one answer to whether this coordinator may create `pane`'s
    /// terminal surface right now, resolved through the accepted generation's
    /// custody ledger. `nil` accepted generation (pre-boot, or a test harness
    /// that never installed a cohort) means no cohort could possibly claim
    /// the pane, so creation is authorized — matching `ViewRegistry`'s own
    /// "no entry, or a stale generation" release rule.
    func terminalSurfaceCreationAuthority(for pane: Pane) -> TerminalSurfaceCreationAuthority? {
        let paneID = PaneId(existingUUID: pane.id)
        guard let generation = acceptedPreparedContentMountGeneration else {
            return .released(paneID)
        }
        return viewRegistry.terminalSurfaceCreationAuthority(for: paneID, generation: generation)
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
            unregisterHostedView(for: pane.id)
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
    /// `authority` is a compile-time witness only: the caller must already
    /// hold one (minted by `ViewRegistry` or the prepared admission port), so
    /// a creation path that skips the custody question does not build. This
    /// function does not branch on its case.
    func createTopologyIndependentTerminalView(
        for pane: Pane,
        initialFrame: NSRect? = nil,
        treatAsRestoredSessionStart: Bool = false,
        authority: TerminalSurfaceCreationAuthority
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
            unregisterHostedView(for: pane.id)
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
            unregisterHostedView(for: paneId)
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

    func unregisterHostedView(for paneId: UUID) {
        viewRegistry.unregister(paneId)
        recoverZoomCompanionAfterResourceLoss(for: paneId)
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

    /// SPEC R5 retry, and the R1 clause that hidden, minimized, and collapsed
    /// panes hydrate once geometry becomes safe. Reevaluates canonical
    /// geometry for exactly the terminal panes the prepared lane still holds
    /// under `deferredGeometry` custody in the accepted generation, and
    /// requeues only those whose placement is no longer ambiguous.
    /// Deliberately never filtered by presentation: a hidden, minimized,
    /// collapsed, or residency-backgrounded pane is included whenever its
    /// canonical frame is now safe. Called as a tail from every
    /// canonical-layout-changing action (`+ActionExecution.swift`) and from
    /// the trusted container-layout callback (`PaneTabViewController`, via
    /// `WorkspaceActionExecutor`); adds no timer, poll, observer, or bus case
    /// of its own.
    func reevaluatePreparedTerminalGeometry() async {
        guard let generation = acceptedPreparedContentMountGeneration else { return }
        let deferredPaneIDs = viewRegistry.deferredPreparedContentMountPaneIDs(
            owner: .terminal,
            generation: generation
        )
        guard !deferredPaneIDs.isEmpty else { return }
        let terminalContainerBounds = windowLifecycleStore.terminalContainerBounds
        guard !terminalContainerBounds.isEmpty else { return }

        let resolvedPaneFramesByTabId = resolveInitialFramesByTabId(in: terminalContainerBounds)
        var resolvedFramesByPaneID: [PaneId: NSRect] = [:]
        for paneID in deferredPaneIDs {
            guard let pane = store.paneAtom.pane(paneID.uuid) else { continue }
            guard
                let frame = initialFrame(for: pane, resolvedPaneFramesByTabId: resolvedPaneFramesByTabId)
            else { continue }
            resolvedFramesByPaneID[paneID] = frame
        }
        guard !resolvedFramesByPaneID.isEmpty else { return }

        // Recorded BEFORE the requeue, not after: `acceptLaterGeometry`
        // enables a drain before this `await` even returns, so an
        // earlier-ordinal hidden competitor could otherwise claim on the
        // still-old revision while this call is suspended, and nothing
        // would repair it afterward — the port and scheduler would simply
        // agree on that stale revision. `handleVisibilitySignals` already
        // treats `.deferredGeometry(owner: .terminal)` custody like
        // `pending` (the deferred pane enters the queued set the same way),
        // so this pre-requeue record already names every pane this call is
        // about to make eligible, at its correct promoted tier (SPEC R3).
        // Any claim the drain proposes carrying the older revision is
        // answered `.visibilityChanged`, and the scheduler applies this
        // snapshot (R3's `admitWaitingMembers` plus `applyVisibilitySnapshot`)
        // before granting anything.
        _ = preparedContentVisibilitySignalHandler(currentVisibleQueuedSet())
        await preparedTerminalGeometryReevaluationHandler(resolvedFramesByPaneID)
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
            result[tab.id] = resolveInitialFrames(for: tab, in: terminalContainerBounds)
        }
    }

    func resolveInitialFrames(for tab: Tab, in terminalContainerBounds: CGRect) -> [UUID: CGRect] {
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

        // Bootstrap geometry is residency- and expansion-independent (SPEC R1,
        // R7): a drawer child needs a frame the instant its terminal admits,
        // whether its drawer is collapsed or its parent is backgrounded. This
        // iterates the canonical `tab.activePaneIds` (already
        // `activeArrangement.layout.paneIds` — never residency-filtered) and
        // reads `drawerViews[ownedDrawerID]` straight from the canonical
        // arrangement via the pane's structural facts. It deliberately does
        // not route through `arrangementView.drawerView(forParent:)`, whose
        // `isActivePane` requirement is exactly the residency filter this
        // slice removes.
        for paneId in tab.activePaneIds {
            guard
                let parentFrame = resolvedFrames[paneId],
                let ownedDrawerID = store.paneAtom.graphAtom.paneStructuralFacts(paneId)?.ownedDrawerID,
                let drawerView = tab.activeArrangement.drawerViews[ownedDrawerID],
                let drawerContentRect = resolvedDrawerContentRect(
                    parentPaneFrame: parentFrame,
                    tabSize: terminalContainerBounds.size
                )
            else {
                continue
            }
            let drawerFrames = TerminalPaneGeometryResolver.resolveFrames(
                for: drawerView.layout,
                in: drawerContentRect,
                dividerThickness: AppStyles.General.Layout.paneGap,
                minimizedPaneIds: drawerView.minimizedPaneIds,
                collapsedPaneWidth: AppStyles.Shell.PaneChrome.collapsedBarWidth
            )

            for (drawerPaneId, drawerPaneFrame) in drawerFrames
            where Self.isFiniteNonEmptyFrame(drawerPaneFrame) {
                resolvedFrames[drawerPaneId] = drawerPaneFrame
            }
        }
        return resolvedFrames
    }

    /// Finite, positive-area frame check shared by the bootstrap geometry
    /// path (SPEC R1's "omit any frame that is empty, negative, or
    /// non-finite" rule) — a pane with no safe frame here is left absent from
    /// `resolvedFrames` so the terminal activation lane defers it rather than
    /// admitting a garbage rect.
    private static func isFiniteNonEmptyFrame(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite
            && rect.origin.y.isFinite
            && rect.size.width.isFinite
            && rect.size.height.isFinite
            && rect.size.width > 0
            && rect.size.height > 0
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
