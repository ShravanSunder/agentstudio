import AppKit
import GhosttyKit

private actor TerminationDeliveryObservation {
    private var hasObservedHandling = false

    func markHandled() {
        hasObservedHandling = true
    }

    func handled() -> Bool {
        hasObservedHandling
    }
}

/// Host-side terminal pane container for Ghostty surfaces, overlays, and lifecycle UI.
/// PaneCoordinator creates surfaces and passes them here via displaySurface().
final class TerminalPaneMountView: NSView, PaneMountedContent, SurfaceHealthDelegate {
    private static let terminationHandlingRetryTurns = 20

    let paneId: UUID
    let worktree: Worktree?
    let repo: Repo?

    var surfaceId: UUID?

    // MARK: - Private State

    private(set) var ghosttySurface: Ghostty.SurfaceView?
    private let ghosttyMountView = GhosttyMountView()
    private(set) var surfaceScrollView: TerminalSurfaceScrollView?
    var searchOverlayView: TerminalSearchOverlayView?
    var scrollToBottomIndicatorView: ScrollToBottomIndicatorView?
    private(set) weak var boundRuntime: TerminalRuntime?
    private var actionPerformerOverrideForTesting: (any TerminalSurfaceActionPerforming)?
    private(set) var isProcessRunning = false
    private(set) var errorOverlay: SurfaceErrorOverlayView?
    private(set) var startupOverlay: SurfaceStartupOverlayView?
    private(set) var placeholderView: TerminalStatusPlaceholderView?
    private let fallbackTitle: String
    private let showsRestorePresentationDuringStartup: Bool
    private let startupGraceDuration: Duration
    private var startupPresentationTask: Task<Void, Never>?
    private var startupPresentationActive = false
    private(set) var shouldSuppressProcessExitedOverlayAfterTermination = false
    private(set) var hasObservedEffectiveTerminationDelivery = false
    private weak var observedRuntime: TerminalRuntime?
    private weak var runtimeBoundToDisplayedSurface: TerminalRuntime?
    var onRepairRequested: ((UUID) -> Void)?

    /// The current terminal title
    var title: String {
        ghosttySurface?.title ?? worktree?.name ?? fallbackTitle
    }

    // MARK: - Initialization

    /// Primary initializer — used by PaneCoordinator for worktree-bound panes.
    /// Does NOT create a surface; caller must attach one via displaySurface().
    init(
        worktree: Worktree,
        repo: Repo,
        restoredSurfaceId: UUID,
        paneId: UUID,
        showsRestorePresentationDuringStartup: Bool = false,
        startupGraceDuration: Duration = .milliseconds(100)
    ) {
        self.paneId = paneId
        self.worktree = worktree
        self.repo = repo
        self.surfaceId = restoredSurfaceId
        self.fallbackTitle = worktree.name
        self.showsRestorePresentationDuringStartup = showsRestorePresentationDuringStartup
        self.startupGraceDuration = startupGraceDuration
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        setupMountView()

        // Register for health updates
        SurfaceManager.shared.addHealthDelegate(self)
        self.isProcessRunning = true
    }

    /// Floating terminal initializer — used for drawers and standalone terminals.
    /// No worktree/repo context required.
    init(
        restoredSurfaceId: UUID,
        paneId: UUID,
        title: String = "Terminal",
        showsRestorePresentationDuringStartup: Bool = false,
        startupGraceDuration: Duration = .milliseconds(100)
    ) {
        self.paneId = paneId
        self.worktree = nil
        self.repo = nil
        self.surfaceId = restoredSurfaceId
        self.fallbackTitle = title
        self.showsRestorePresentationDuringStartup = showsRestorePresentationDuringStartup
        self.startupGraceDuration = startupGraceDuration
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        setupMountView()

        SurfaceManager.shared.addHealthDelegate(self)
        self.isProcessRunning = true
    }

    /// Placeholder-only initializer used before a surface exists.
    init(
        paneId: UUID,
        title: String
    ) {
        self.paneId = paneId
        self.worktree = nil
        self.repo = nil
        self.surfaceId = nil
        self.fallbackTitle = title
        self.showsRestorePresentationDuringStartup = false
        self.startupGraceDuration = .milliseconds(100)
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        setupMountView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    isolated deinit {
        startupPresentationTask?.cancel()
        // Safety net: coordinator.teardownView() should have detached before dealloc.
        // If surfaceId is still set, the normal teardown path was missed.
        if let surfaceId {
            debugLog(
                "[TerminalPaneMountView] WARNING: deinit with surfaceId \(surfaceId) still attached — teardown was missed"
            )
        }
    }

    // MARK: - Layout

    private func setupMountView() {
        ghosttyMountView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ghosttyMountView)
        NSLayoutConstraint.activate([
            ghosttyMountView.topAnchor.constraint(equalTo: topAnchor),
            ghosttyMountView.leadingAnchor.constraint(equalTo: leadingAnchor),
            ghosttyMountView.trailingAnchor.constraint(equalTo: trailingAnchor),
            ghosttyMountView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    var currentActionPerformer: (any TerminalSurfaceActionPerforming)? {
        actionPerformerOverrideForTesting ?? ghosttySurface
    }

    private var lastReportedSurfaceSize: NSSize = .zero

    override func layout() {
        super.layout()
        guard let surface = ghosttySurface, bounds.size.width > 0, bounds.size.height > 0 else { return }
        let currentSize = measuredSurfaceSize(for: surface)
        guard currentSize != lastReportedSurfaceSize else { return }
        lastReportedSurfaceSize = currentSize
        RestoreTrace.log(
            "TerminalPaneMountView.layout pane=\(paneId) surface=\(surfaceId?.uuidString ?? "nil") paneBounds=\(NSStringFromRect(bounds)) surfaceBounds=\(NSStringFromRect(surface.bounds)) surfaceMetrics={\(surface.metricsSnapshotDescription())}"
        )
        surface.sizeDidChange(currentSize, source: "mountView.layout")
    }

    func forceGeometrySync(reason: StaticString) {
        guard let surface = ghosttySurface, window != nil else { return }
        guard bounds.size.width > 0, bounds.size.height > 0 else { return }
        layoutSubtreeIfNeeded()
        let actualSurfaceSize = measuredSurfaceSize(for: surface)
        guard actualSurfaceSize.width > 0, actualSurfaceSize.height > 0 else { return }
        lastReportedSurfaceSize = .zero
        RestoreTrace.log(
            "TerminalPaneMountView.forceGeometrySync pane=\(paneId) surface=\(surfaceId?.uuidString ?? "nil") reason=\(reason) paneBounds=\(NSStringFromRect(bounds)) surfaceBounds=\(NSStringFromRect(surface.bounds)) surfaceMetrics={\(surface.metricsSnapshotDescription())}"
        )
        surface.sizeDidChange(actualSurfaceSize, source: "forceGeometrySync")
    }

    /// During the first layout tick after mount, AppKit can call through before
    /// the constrained Ghostty mount view has published non-zero bounds. Falling
    /// back to the surface's own frame keeps the initial geometry sync stable
    /// without turning that transient timing window into a zero-size resize.
    private func measuredSurfaceSize(for surface: Ghostty.SurfaceView) -> NSSize {
        let mountSize = ghosttyMountView.bounds.size
        return mountSize == .zero ? surface.bounds.size : mountSize
    }

    // MARK: - Surface Display

    func displaySurface(_ surfaceView: Ghostty.SurfaceView) {
        let previouslyDisplayedSurface = ghosttySurface
        // Remove existing surface if any
        ghosttySurface?.onCloseRequested = nil
        ghosttyMountView.unmountCurrentView()
        clearPlaceholder()
        RestoreTrace.log(
            "TerminalPaneMountView.displaySurface pane=\(paneId) surface=\(surfaceId?.uuidString ?? "nil") hostBounds=\(NSStringFromRect(bounds)) incomingSurfaceFrame=\(NSStringFromRect(surfaceView.frame)) incomingSurfaceMetrics={\(surfaceView.metricsSnapshotDescription())}"
        )

        let wrappedScrollView = TerminalSurfaceScrollView(actionPerformer: surfaceView)
        wrappedScrollView.embedSurfaceView(surfaceView)
        ghosttyMountView.mount(wrappedScrollView)

        self.ghosttySurface = surfaceView
        self.surfaceScrollView = wrappedScrollView
        self.lastReportedSurfaceSize = .zero
        self.shouldSuppressProcessExitedOverlayAfterTermination = false
        self.hasObservedEffectiveTerminationDelivery = false
        RestoreTrace.log(
            "TerminalPaneMountView.displaySurface mounted pane=\(paneId) surface=\(surfaceId?.uuidString ?? "nil") mountedSurfaceMetrics={\(surfaceView.metricsSnapshotDescription())}"
        )

        // Make this view layer-backed AFTER the surface is created
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor

        beginRestorePresentationIfNeeded()
        ensureScrollToBottomIndicator()
        if let boundRuntime {
            if observedRuntime !== boundRuntime {
                observedRuntime = boundRuntime
                observeRuntimeState(runtime: boundRuntime)
            }
            applyRuntimeStateSnapshot(boundRuntime)
            if runtimeBoundToDisplayedSurface !== boundRuntime || previouslyDisplayedSurface !== surfaceView {
                surfaceView.bindRuntime(boundRuntime)
                runtimeBoundToDisplayedSurface = boundRuntime
            }
        }
        surfaceView.onCloseRequested = { [weak self] processAlive in
            self?.handleSurfaceClose(processAlive: processAlive)
        }
    }

    func removeSurface() {
        ghosttySurface?.onCloseRequested = nil
        ghosttyMountView.unmountCurrentView()
        ghosttySurface = nil
        surfaceScrollView = nil
        boundRuntime = nil
        observedRuntime = nil
        runtimeBoundToDisplayedSurface = nil
        surfaceId = nil
        shouldSuppressProcessExitedOverlayAfterTermination = false
        hasObservedEffectiveTerminationDelivery = false
    }

    func bind(runtime: TerminalRuntime) {
        let shouldObserveRuntime = observedRuntime !== runtime
        boundRuntime = runtime
        applyRuntimeStateSnapshot(runtime)
        if let ghosttySurface, runtimeBoundToDisplayedSurface !== runtime {
            ghosttySurface.bindRuntime(runtime)
            runtimeBoundToDisplayedSurface = runtime
        }
        if shouldObserveRuntime {
            observedRuntime = runtime
            observeRuntimeState(runtime: runtime)
        }
    }

    func installActionPerformerForTesting(_ performer: any TerminalSurfaceActionPerforming) {
        actionPerformerOverrideForTesting = performer
        scrollToBottomIndicatorView?.actionPerformer = performer
    }

    override func cancelOperation(_ sender: Any?) {
        if handleSearchCancelOperation(sender) {
            return
        }
    }

    @discardableResult
    func showPlaceholder(
        mode: TerminalStatusPlaceholderMode,
        onRetryRequested: ((UUID) -> Void)? = nil,
        onDismissRequested: ((UUID) -> Void)? = nil
    ) -> TerminalStatusPlaceholderView {
        if let placeholderView {
            placeholderView.configure(mode: mode)
            return placeholderView
        }

        let placeholder = TerminalStatusPlaceholderView(
            paneId: paneId,
            title: title,
            mode: mode,
            onRetryRequested: onRetryRequested,
            onDismissRequested: onDismissRequested
        )
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: topAnchor),
            placeholder.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: trailingAnchor),
            placeholder.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        placeholderView = placeholder
        return placeholder
    }

    func clearPlaceholder() {
        placeholderView?.removeFromSuperview()
        placeholderView = nil
    }

    // MARK: - SurfaceHealthDelegate

    func surface(_ surfaceId: UUID, healthChanged health: SurfaceHealth) {
        guard surfaceId == self.surfaceId else { return }

        Task { @MainActor [weak self] in
            self?.updateHealthUI(health)
        }
    }

    func surface(_ surfaceId: UUID, didEncounterError error: SurfaceError) {
        guard surfaceId == self.surfaceId else { return }

        Task { @MainActor [weak self] in
            self?.showErrorOverlay(health: .dead)
        }
    }

    func updateHealthUI(_ health: SurfaceHealth) {
        if case .processExited = health,
            !isProcessRunning,
            shouldSuppressProcessExitedOverlayAfterTermination
        {
            finishRestorePresentation()
            hideErrorOverlay()
            return
        }

        if startupPresentationActive {
            switch health {
            case .healthy:
                finishRestorePresentation()
            case .unhealthy, .processExited, .dead:
                failRestorePresentation(health: health)
                return
            }
        }

        if health.isHealthy {
            hideErrorOverlay()
        } else {
            showErrorOverlay(health: health)
        }
    }

    // MARK: - Error Overlay

    private func showErrorOverlay(health: SurfaceHealth) {
        if errorOverlay == nil {
            let overlay = SurfaceErrorOverlayView()
            overlay.translatesAutoresizingMaskIntoConstraints = false
            overlay.onRestart = { [weak self] in
                self?.restartSurface()
            }
            overlay.onDismiss = { [weak self] in
                self?.requestClose()
            }
            addSubview(overlay)

            NSLayoutConstraint.activate([
                overlay.topAnchor.constraint(equalTo: topAnchor),
                overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
                overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])

            errorOverlay = overlay
        }

        errorOverlay?.configure(health: health)
    }

    private func hideErrorOverlay() {
        errorOverlay?.hide()
    }

    private func restartSurface() {
        guard let oldSurfaceId = surfaceId else { return }

        // Destroy old surface
        SurfaceManager.shared.destroy(oldSurfaceId)
        removeSurface()

        // Request coordinator to recreate the surface
        onRepairRequested?(paneId)
        hideErrorOverlay()
    }

    // MARK: - Surface Close Handling

    func handleSurfaceClose(processAlive: Bool) {
        guard isProcessRunning else { return }
        isProcessRunning = false
        shouldSuppressProcessExitedOverlayAfterTermination = true
        hasObservedEffectiveTerminationDelivery = false
        RestoreTrace.log(
            "TerminalPaneMountView.handleSurfaceClose pane=\(paneId) surface=\(surfaceId?.uuidString ?? "nil") processAlive=\(processAlive)"
        )
        postProcessTerminationEvent(processAlive: processAlive)
    }

    func beginRestorePresentationIfNeeded() {
        guard showsRestorePresentationDuringStartup else { return }
        startupPresentationTask?.cancel()
        startupPresentationActive = true
        showStartupOverlay()
        startupPresentationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: startupGraceDuration.nanosecondsForTaskSleep)
            } catch is CancellationError {
                return
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let revealState = HiddenSurfaceReadiness.revealState(
                processExited: self.processExited,
                startupWindowElapsed: true
            )
            switch revealState {
            case .restoring:
                self.showStartupOverlay()
            case .reveal:
                self.finishRestorePresentation()
            case .failed:
                self.failRestorePresentation(health: .processExited(exitCode: nil))
            }
        }
    }

    private func showStartupOverlay() {
        if startupOverlay == nil {
            let overlay = SurfaceStartupOverlayView()
            overlay.translatesAutoresizingMaskIntoConstraints = false
            addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.topAnchor.constraint(equalTo: topAnchor),
                overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
                overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            startupOverlay = overlay
        }
        startupOverlay?.showRestoring()
    }

    private func finishRestorePresentation() {
        startupPresentationTask?.cancel()
        startupPresentationTask = nil
        startupPresentationActive = false
        startupOverlay?.hide()
    }

    private func failRestorePresentation(health: SurfaceHealth) {
        startupPresentationTask?.cancel()
        startupPresentationTask = nil
        startupPresentationActive = false
        startupOverlay?.hide()
        showErrorOverlay(health: health)
    }

    // MARK: - Process Management

    func requestClose() {
        guard let surfaceId else { return }
        SurfaceManager.shared.detach(surfaceId, reason: .close)
        isProcessRunning = false
        shouldSuppressProcessExitedOverlayAfterTermination = true
        hasObservedEffectiveTerminationDelivery = false
        postProcessTerminationEvent(processAlive: true)
    }

    func terminateProcess() {
        guard isProcessRunning, let surfaceId else { return }
        isProcessRunning = false
        SurfaceManager.shared.destroy(surfaceId)
        self.surfaceId = nil
        shouldSuppressProcessExitedOverlayAfterTermination = false
        hasObservedEffectiveTerminationDelivery = false
    }

    private func postProcessTerminationEvent(processAlive: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let terminationObservation = TerminationDeliveryObservation()
            let paneId = self.paneId
            let acknowledgementTask = Task {
                let stream = await AppEventBus.shared.subscribe()
                for await event in stream {
                    switch event {
                    case .terminalProcessTerminationHandled(let handledPaneId) where handledPaneId == paneId:
                        await terminationObservation.markHandled()
                        return
                    default:
                        continue
                    }
                }
            }

            _ = await AppEventBus.shared.post(.terminalProcessTerminated(paneId: paneId))
            let hadEffectiveDelivery = await self.waitForTerminationHandling(
                observation: terminationObservation,
                acknowledgementTask: acknowledgementTask
            )
            self.hasObservedEffectiveTerminationDelivery = hadEffectiveDelivery
            if hadEffectiveDelivery {
                self.finishRestorePresentation()
                self.hideErrorOverlay()
                return
            }
            self.shouldSuppressProcessExitedOverlayAfterTermination = false
            self.showProcessExitedFallback(processAlive: processAlive)
        }
    }

    private func waitForTerminationHandling(
        observation: TerminationDeliveryObservation,
        acknowledgementTask: Task<Void, Never>
    ) async -> Bool {
        defer { acknowledgementTask.cancel() }

        for _ in 0..<Self.terminationHandlingRetryTurns {
            if await observation.handled() {
                return true
            }
            await Task.yield()
        }

        return await observation.handled()
    }

    private func showProcessExitedFallback(processAlive: Bool) {
        let fallbackHealth: SurfaceHealth = .processExited(exitCode: nil)
        if startupPresentationActive {
            failRestorePresentation(health: fallbackHealth)
        } else {
            showErrorOverlay(health: fallbackHealth)
        }
        RestoreTrace.log(
            "TerminalPaneMountView.showProcessExitedFallback pane=\(paneId) surface=\(surfaceId?.uuidString ?? "nil") processAlive=\(processAlive)"
        )
    }

    var processExited: Bool {
        guard let surfaceId else { return true }
        return SurfaceManager.shared.hasProcessExited(surfaceId)
    }

    func setContentInteractionEnabled(_ enabled: Bool) {
        _ = enabled
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        if let surface = ghosttySurface, let window {
            if let surfaceId {
                SurfaceManager.shared.setFocus(surfaceId, focused: true)
            }
            RestoreTrace.log(
                "TerminalPaneMountView.becomeFirstResponder pane=\(paneId) surface=\(surfaceId?.uuidString ?? "nil")")
            return window.makeFirstResponder(surface)
        }
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        if let surfaceId {
            SurfaceManager.shared.setFocus(surfaceId, focused: false)
        }
        RestoreTrace.log(
            "TerminalPaneMountView.resignFirstResponder pane=\(paneId) surface=\(surfaceId?.uuidString ?? "nil")")
        return super.resignFirstResponder()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        resolvedHitTest(for: point) ?? super.hitTest(point)
    }

    /// The current placeholder view, if one is shown. Used by coordinators
    /// to check placeholder state during repair and re-registration flows.
    var currentPlaceholderView: TerminalStatusPlaceholderView? { placeholderView }
}

#if DEBUG
    @MainActor
    extension TerminalPaneMountView {
        func installSurfaceScrollViewForTesting(_ scrollView: TerminalSurfaceScrollView) {
            surfaceScrollView = scrollView
        }
    }
#endif
