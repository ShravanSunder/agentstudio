import AppKit
import GhosttyKit

/// Terminal view wrapping Ghostty's SurfaceView via SurfaceManager.
/// This is a host-only view — PaneCoordinator creates surfaces and
/// passes them here via displaySurface(). The view never creates its own surfaces.
final class AgentStudioTerminalView: PaneView, SurfaceHealthDelegate {
    let worktree: Worktree?
    let repo: Repo?

    var surfaceId: UUID?

    // MARK: - Private State

    private var ghosttySurface: Ghostty.SurfaceView?
    private(set) var isProcessRunning = false
    private var errorOverlay: SurfaceErrorOverlayView?
    private let fallbackTitle: String
    private var surfaceCloseObserver: NSObjectProtocol?

    /// The current terminal title
    var title: String {
        ghosttySurface?.title ?? worktree?.name ?? fallbackTitle
    }

    // MARK: - Initialization

    /// Primary initializer — used by PaneCoordinator for worktree-bound panes.
    /// Does NOT create a surface; caller must attach one via displaySurface().
    init(worktree: Worktree, repo: Repo, restoredSurfaceId: UUID, paneId: UUID) {
        self.worktree = worktree
        self.repo = repo
        self.surfaceId = restoredSurfaceId
        self.fallbackTitle = worktree.name
        super.init(paneId: paneId)

        // Register for health updates
        SurfaceManager.shared.addHealthDelegate(self)
        self.isProcessRunning = true
    }

    /// Floating terminal initializer — used for drawers and standalone terminals.
    /// No worktree/repo context required.
    init(restoredSurfaceId: UUID, paneId: UUID, title: String = "Terminal") {
        self.worktree = nil
        self.repo = nil
        self.surfaceId = restoredSurfaceId
        self.fallbackTitle = title
        super.init(paneId: paneId)

        SurfaceManager.shared.addHealthDelegate(self)
        self.isProcessRunning = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    isolated deinit {
        if let observer = surfaceCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        // Safety net: coordinator.teardownView() should have detached before dealloc.
        // If surfaceId is still set, the normal teardown path was missed.
        if let surfaceId {
            debugLog(
                "[AgentStudioTerminalView] WARNING: deinit with surfaceId \(surfaceId) still attached — teardown was missed"
            )
        }
    }

    // MARK: - Layout

    private var lastReportedSurfaceSize: NSSize = .zero

    override func layout() {
        super.layout()
        guard let surface = ghosttySurface, bounds.size.width > 0, bounds.size.height > 0 else { return }
        let currentSize = surface.bounds.size
        guard currentSize != lastReportedSurfaceSize else { return }
        lastReportedSurfaceSize = currentSize
        RestoreTrace.log(
            "AgentStudioTerminalView.layout pane=\(paneId) surface=\(surfaceId?.uuidString ?? "nil") paneBounds=\(NSStringFromRect(bounds)) surfaceBounds=\(NSStringFromRect(surface.bounds))"
        )
        surface.sizeDidChange(currentSize)
    }

    // MARK: - Surface Display

    func displaySurface(_ surfaceView: Ghostty.SurfaceView) {
        // Remove existing surface if any
        ghosttySurface?.removeFromSuperview()
        RestoreTrace.log(
            "AgentStudioTerminalView.displaySurface pane=\(paneId) surface=\(surfaceId?.uuidString ?? "nil") hostBounds=\(NSStringFromRect(bounds)) incomingSurfaceFrame=\(NSStringFromRect(surfaceView.frame))"
        )

        surfaceView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surfaceView)

        NSLayoutConstraint.activate([
            surfaceView.topAnchor.constraint(equalTo: topAnchor),
            surfaceView.leadingAnchor.constraint(equalTo: leadingAnchor),
            surfaceView.trailingAnchor.constraint(equalTo: trailingAnchor),
            surfaceView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        self.ghosttySurface = surfaceView
        self.lastReportedSurfaceSize = .zero
        RestoreTrace.log(
            "AgentStudioTerminalView.displaySurface mounted pane=\(paneId) surface=\(surfaceId?.uuidString ?? "nil")"
        )

        // Make this view layer-backed AFTER the surface is created
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor

        // Listen for surface close
        if let observer = surfaceCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        surfaceCloseObserver = NotificationCenter.default.addObserver(
            forName: .ghosttyCloseSurface,
            object: surfaceView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSurfaceClose()
            }
        }
    }

    func removeSurface() {
        ghosttySurface?.removeFromSuperview()
        ghosttySurface = nil
        surfaceId = nil
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

    private func updateHealthUI(_ health: SurfaceHealth) {
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
        NotificationCenter.default.post(
            name: .repairSurfaceRequested,
            object: nil,
            userInfo: ["paneId": paneId]
        )
        hideErrorOverlay()
    }

    // MARK: - Surface Close Handling

    private func handleSurfaceClose() {
        guard isProcessRunning else { return }
        isProcessRunning = false
        RestoreTrace.log(
            "AgentStudioTerminalView.handleSurfaceClose pane=\(paneId) surface=\(surfaceId?.uuidString ?? "nil")"
        )
        handleProcessTerminated(exitCode: nil)
    }

    // MARK: - Process Management

    /// `exitCode == nil` means the process terminated without a reliable numeric
    /// code (e.g. surface-level close callback / force-destroy path).
    func handleProcessTerminated(exitCode: Int32?) {
        isProcessRunning = false
        var userInfo: [String: Any] = ["exitCode": exitCode as Any]
        if let worktreeId = worktree?.id {
            userInfo["worktreeId"] = worktreeId
        }
        NotificationCenter.default.post(
            name: .terminalProcessTerminated,
            object: self,
            userInfo: userInfo
        )
    }

    func requestClose() {
        guard let surfaceId else { return }
        SurfaceManager.shared.detach(surfaceId, reason: .close)
        handleProcessTerminated(exitCode: nil)
    }

    func terminateProcess() {
        guard isProcessRunning, let surfaceId else { return }
        isProcessRunning = false
        SurfaceManager.shared.destroy(surfaceId)
        self.surfaceId = nil
    }

    var processExited: Bool {
        guard let surfaceId else { return true }
        return SurfaceManager.shared.hasProcessExited(surfaceId)
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        if let surface = ghosttySurface, let window {
            if let surfaceId {
                SurfaceManager.shared.setFocus(surfaceId, focused: true)
            }
            RestoreTrace.log(
                "AgentStudioTerminalView.becomeFirstResponder pane=\(paneId) surface=\(surfaceId?.uuidString ?? "nil")")
            return window.makeFirstResponder(surface)
        }
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        if let surfaceId {
            SurfaceManager.shared.setFocus(surfaceId, focused: false)
        }
        RestoreTrace.log(
            "AgentStudioTerminalView.resignFirstResponder pane=\(paneId) surface=\(surfaceId?.uuidString ?? "nil")")
        return super.resignFirstResponder()
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Management mode: delegate to PaneView base class (uses interaction shield)
        if ManagementModeMonitor.shared.isActive {
            return super.hitTest(point)
        }

        // Normal mode: custom routing for error overlay and Ghostty surface
        if let overlay = errorOverlay, !overlay.isHidden {
            let overlayPoint = convert(point, to: overlay)
            if overlay.bounds.contains(overlayPoint) {
                return overlay.hitTest(overlayPoint)
            }
        }

        if let surface = ghosttySurface, bounds.contains(point) {
            return surface
        }
        return super.hitTest(point)
    }

}
