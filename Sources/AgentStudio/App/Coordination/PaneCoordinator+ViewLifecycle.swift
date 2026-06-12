import AppKit
import Foundation
import GhosttyKit

@MainActor
extension PaneCoordinator {
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

    static func floatingZmxRestoreSessionId(for pane: Pane, launchDirectory: URL) -> String {
        if let parentPaneId = pane.parentPaneId {
            return ZmxBackend.drawerSessionId(
                parentPaneId: parentPaneId,
                drawerPaneId: pane.id
            )
        }

        return ZmxBackend.floatingSessionId(
            launchDirectory: launchDirectory,
            paneId: pane.id
        )
    }

    /// Create a view for any pane content type. Dispatches to the appropriate factory.
    /// Returns the created mounted content view, or nil on failure.
    func createViewForContent(
        pane: Pane,
        initialFrame: NSRect? = nil,
        treatAsRestoredSessionStart: Bool = false
    ) -> NSView? {
        let createStart = RestoreTrace.nowIfEnabled()
        let createdView: NSView? = {
            viewRegistry.ensureSlot(for: pane.id)
            registerPaneFilesystemContextIfNeeded(for: pane)

            switch pane.content {
            case .terminal:
                if let worktreeId = pane.worktreeId,
                    let repoId = pane.repoId,
                    let worktree = store.repositoryTopologyAtom.worktree(worktreeId),
                    let repo = store.repositoryTopologyAtom.repo(repoId)
                {
                    return createView(
                        for: pane,
                        worktree: worktree,
                        repo: repo,
                        initialFrame: initialFrame,
                        treatAsRestoredSessionStart: treatAsRestoredSessionStart
                    )

                } else if let parentPaneId = pane.parentPaneId,
                    let parentPane = store.paneAtom.pane(parentPaneId),
                    let worktreeId = parentPane.worktreeId,
                    let repoId = parentPane.repoId,
                    let worktree = store.repositoryTopologyAtom.worktree(worktreeId),
                    let repo = store.repositoryTopologyAtom.repo(repoId)
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
                let view = WebviewPaneMountView(paneId: pane.id, state: state)
                let paneId = pane.id
                view.controller.onTitleChange = { [weak self] title in
                    self?.store.paneAtom.updatePaneTitle(paneId, title: title)
                }
                registerHostedView(mountedView: view, for: pane.id)
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

                let view = CodeViewerPaneMountView(
                    paneId: pane.id,
                    state: state,
                    initialText: initialText
                )
                registerHostedView(mountedView: view, for: pane.id)
                Self.logger.info("Created code viewer pane \(pane.id)")
                return view

            case .bridgePanel(let state):
                let controller = BridgePaneController(paneId: pane.id, state: state)
                let view = BridgePaneMountView(paneId: pane.id, controller: controller)
                registerHostedView(mountedView: view, for: pane.id)
                registerRuntimeIfNeeded(runtime: view.runtime, for: pane)
                controller.loadApp()
                Self.logger.info("Created bridge panel view for pane \(pane.id)")
                return view

            case .unsupported:
                Self.logger.warning("Cannot create view for unsupported content type — pane \(pane.id)")
                return nil
            }
        }()
        RestoreTrace.logDuration(
            "surface_create",
            start: createStart,
            fields: restoreTraceFields(
                for: pane,
                outcome: createdView == nil ? "failed" : "created"
            )
        )
        return createdView
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
                showsRestorePresentationDuringStartup: startupPreparation.showsRestorePresentationDuringStartup
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
    private func createFloatingTerminalView(
        for pane: Pane,
        initialFrame: NSRect? = nil,
        treatAsRestoredSessionStart: Bool = false
    ) -> TerminalPaneMountView? {
        if pane.provider == .zmx, initialFrame == nil {
            RestoreTrace.log(
                "createFloatingTerminalView deferred pane=\(pane.id) reason=missingInitialFrame"
            )
            Self.logger.warning(
                "Deferring floating zmx pane \(pane.id, privacy: .public) until trusted initialFrame exists"
            )
            registerTerminalPlaceholderIfNeeded(for: pane, mode: .preparing)
            return nil
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
        else { return nil }

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
            surfaceManager.attach(managed.id, to: pane.id)
            traceSurfaceAttached(pane: pane, surfaceID: managed.id)

            let view = TerminalPaneMountView(
                restoredSurfaceId: managed.id,
                paneId: pane.id,
                title: pane.metadata.title,
                showsRestorePresentationDuringStartup: startupPreparation.showsRestorePresentationDuringStartup
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
            RestoreTrace.log("createFloatingView complete pane=\(pane.id) surface=\(managed.id)")

            Self.logger.info("Created floating terminal view for pane \(pane.id)")
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
                "createFloatingSurface failure pane=\(pane.id) error=\(error.localizedDescription)"
            )
            Self.logger.error(
                "Failed to create floating surface for pane \(pane.id): \(error.localizedDescription)")
            rollbackPreparedTerminalRuntimeIfNeeded(preparedRuntime)
            registerTerminalPlaceholderIfNeeded(for: pane, mode: .failedToStart)
            return nil
        }
    }

    private func prepareTerminalSurfaceStartup(
        for pane: Pane,
        shellCommand: String,
        treatAsRestoredSessionStart: Bool,
        context: TerminalSurfaceStartupContext
    ) -> TerminalSurfaceStartupPreparation? {
        switch pane.provider {
        case .zmx:
            let diagnostics = terminalRestoreRuntime.zmxAttachDiagnostics(for: pane, store: store)
            if let diagnostics {
                RestoreTrace.log(
                    "\(context.diagnosticsTracePrefix) zmxDiagnostics pane=\(diagnostics.paneId) session=\(diagnostics.sessionId) socketPathLen=\(diagnostics.socketPathLength) socketPathHeadroom=\(diagnostics.socketPathHeadroom) maxSocketPathLen=\(diagnostics.maxSocketPathLength)"
                )
            }
            if let attachCommand = terminalRestoreRuntime.zmxAttachCommand(for: pane, store: store) {
                traceZmxAttachPrepared(pane: pane, diagnostics: diagnostics)
                // Prevent nested Agent Studio launches from inheriting an outer zmx session.
                let environmentVariables: [String: String] = [
                    "ZMX_DIR": sessionConfig.zmxDir,
                    "ZMX_SESSION": "",
                ]
                if case .floating(let launchDirectory) = context {
                    RestoreTrace.log(
                        "createFloatingView zmx pane=\(pane.id) session=\(Self.floatingZmxRestoreSessionId(for: pane, launchDirectory: launchDirectory)) cwd=\(launchDirectory.path)"
                    )
                }
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
        paneFilesystemProjectionStore.unregisterPaneContext(paneId)
        if let terminal = viewRegistry.terminalView(for: paneId),
            let surfaceId = terminal.surfaceId
        {
            surfaceManager.detach(surfaceId, reason: .close)
        }

        if let bridgeView = viewRegistry.view(for: paneId)?.mountedContent(as: BridgePaneMountView.self) {
            bridgeView.controller.teardown()
        }

        viewRegistry.unregister(paneId)
        if shouldUnregisterRuntime {
            if UUIDv7.isV7(paneId) {
                let runtimePaneId = PaneId(uuid: paneId)
                _ = unregisterRuntime(runtimePaneId)
                Task { [paneEventBus] in
                    await paneEventBus.evictReplay(sourceKey: EventSource.pane(runtimePaneId).description)
                }
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
        terminal.displaySurface(surfaceView)
        if let pane = store.paneAtom.pane(paneId) {
            registerTerminalRuntimeIfNeeded(for: pane)
        }
        Self.logger.debug("Reattached pane \(paneId.uuidString, privacy: .public) for view switch")
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

    private func registerPaneFilesystemContextIfNeeded(for pane: Pane) {
        guard let repoId = pane.repoId, let worktreeId = pane.worktreeId else {
            paneFilesystemProjectionStore.unregisterPaneContext(pane.id)
            return
        }

        let fallbackCwd =
            store.repositoryTopologyAtom.worktree(worktreeId)?.path
            ?? pane.metadata.launchDirectory
            ?? pane.metadata.cwd
        guard let fallbackCwd else {
            paneFilesystemProjectionStore.unregisterPaneContext(pane.id)
            return
        }

        paneFilesystemProjectionStore.registerPaneContext(
            PaneFilesystemContext(
                paneId: PaneId(uuid: pane.id),
                repoId: repoId,
                cwd: (pane.metadata.cwd ?? fallbackCwd).standardizedFileURL.resolvingSymlinksInPath(),
                worktreeId: worktreeId
            )
        )
    }

    /// Restore a view from an undo close. Tries to reuse the undone surface; creates fresh if expired.
    @discardableResult
    func restoreView(
        for pane: Pane,
        worktree: Worktree,
        repo: Repo
    ) -> TerminalPaneMountView? {
        guard UUIDv7.isV7(pane.id) else {
            Self.logger.error(
                "Unable to restore runtime for non-v7 pane id \(pane.id.uuidString, privacy: .public)"
            )
            return nil
        }
        let runtimePaneId = PaneId(uuid: pane.id)
        let runtimeWasAlreadyRegistered = runtimeForPane(runtimePaneId) != nil
        if let undone = surfaceManager.undoClose() {
            if undone.metadata.paneId == pane.id {
                let view = TerminalPaneMountView(
                    worktree: worktree,
                    repo: repo,
                    restoredSurfaceId: undone.id,
                    paneId: pane.id
                )
                surfaceManager.attach(undone.id, to: pane.id)
                view.displaySurface(undone.surface)
                registerHostedView(mountedView: view, for: pane.id)
                registerTerminalRuntimeIfNeeded(for: pane)
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

    private func getDefaultShell() -> String {
        SessionConfiguration.defaultShell()
    }
}
