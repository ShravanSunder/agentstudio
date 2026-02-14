import AppKit
import GhosttyKit

/// Terminal view wrapping Ghostty's SurfaceView via SurfaceManager.
/// This is a host-only view — TerminalViewCoordinator creates surfaces and
/// passes them here via displaySurface(). The view never creates its own surfaces.
final class AgentStudioTerminalView: NSView, SurfaceHealthDelegate {
    let worktree: Worktree
    let repo: Repo

    /// Pane identity — used for ViewRegistry keying, SurfaceManager.attach(), etc.
    /// Set once, never changes. Preserved through undo-close.
    let paneId: UUID

    var surfaceId: UUID?

    // MARK: - Private State

    private var ghosttySurface: Ghostty.SurfaceView?
    private(set) var isProcessRunning = false
    private var errorOverlay: SurfaceErrorOverlayView?

    /// The current terminal title
    var title: String {
        ghosttySurface?.title ?? worktree.name
    }

    // MARK: - Initialization

    /// Primary initializer — used by TerminalViewCoordinator.
    /// Does NOT create a surface; caller must attach one via displaySurface().
    init(worktree: Worktree, repo: Repo, restoredSurfaceId: UUID, paneId: UUID) {
        self.paneId = paneId
        self.worktree = worktree
        self.repo = repo
        self.surfaceId = restoredSurfaceId
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        // Register for health updates
        SurfaceManager.shared.addHealthDelegate(self)
        self.isProcessRunning = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    deinit {
        // Safety net: coordinator.teardownView() should have detached before dealloc.
        // If surfaceId is still set, the normal teardown path was missed.
        if let surfaceId = surfaceId {
            debugLog("[AgentStudioTerminalView] WARNING: deinit with surfaceId \(surfaceId) still attached — teardown was missed")
        }
    }

    // MARK: - Surface Display

    func displaySurface(_ surfaceView: Ghostty.SurfaceView) {
        // Remove existing surface if any
        ghosttySurface?.removeFromSuperview()

        surfaceView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surfaceView)

        NSLayoutConstraint.activate([
            surfaceView.topAnchor.constraint(equalTo: topAnchor),
            surfaceView.leadingAnchor.constraint(equalTo: leadingAnchor),
            surfaceView.trailingAnchor.constraint(equalTo: trailingAnchor),
            surfaceView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        self.ghosttySurface = surfaceView

        // Make this view layer-backed AFTER the surface is created
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor

        // Listen for surface close
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSurfaceClose(_:)),
            name: .ghosttyCloseSurface,
            object: surfaceView
        )
    }

    func removeSurface() {
        ghosttySurface?.removeFromSuperview()
        ghosttySurface = nil
        surfaceId = nil
    }

    // MARK: - SurfaceHealthDelegate

    func surface(_ surfaceId: UUID, healthChanged health: SurfaceHealth) {
        guard surfaceId == self.surfaceId else { return }

        DispatchQueue.main.async { [weak self] in
            self?.updateHealthUI(health)
        }
    }

    func surface(_ surfaceId: UUID, didEncounterError error: SurfaceError) {
        guard surfaceId == self.surfaceId else { return }

        DispatchQueue.main.async { [weak self] in
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
                overlay.bottomAnchor.constraint(equalTo: bottomAnchor)
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

    @objc private func handleSurfaceClose(_ notification: Notification) {
        guard isProcessRunning else { return }
        isProcessRunning = false
        handleProcessTerminated(exitCode: 0)
    }

    // MARK: - Process Management

    func handleProcessTerminated(exitCode: Int32?) {
        isProcessRunning = false
        NotificationCenter.default.post(
            name: .terminalProcessTerminated,
            object: self,
            userInfo: ["worktreeId": worktree.id, "exitCode": exitCode as Any]
        )
    }

    func requestClose() {
        guard let surfaceId = surfaceId else { return }
        SurfaceManager.shared.detach(surfaceId, reason: .close)
        handleProcessTerminated(exitCode: nil)
    }

    func terminateProcess() {
        guard isProcessRunning, let surfaceId = surfaceId else { return }
        isProcessRunning = false
        SurfaceManager.shared.destroy(surfaceId)
        self.surfaceId = nil
    }

    var processExited: Bool {
        guard let surfaceId = surfaceId else { return true }
        return SurfaceManager.shared.hasProcessExited(surfaceId)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        guard let surface = ghosttySurface, bounds.size.width > 0, bounds.size.height > 0 else { return }
        surface.sizeDidChange(surface.bounds.size)
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        if let surface = ghosttySurface, let window = window {
            if let surfaceId = surfaceId {
                SurfaceManager.shared.setFocus(surfaceId, focused: true)
            }
            return window.makeFirstResponder(surface)
        }
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        if let surfaceId = surfaceId {
            SurfaceManager.shared.setFocus(surfaceId, focused: false)
        }
        return super.resignFirstResponder()
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
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

    // MARK: - SwiftUI Bridging

    private(set) lazy var swiftUIContainer: NSView = {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        self.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(self)
        NSLayoutConstraint.activate([
            self.topAnchor.constraint(equalTo: container.topAnchor),
            self.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            self.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            self.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }()
}

// MARK: - Identifiable

extension AgentStudioTerminalView: Identifiable {
    typealias ID = UUID
    var id: UUID { paneId }
}
