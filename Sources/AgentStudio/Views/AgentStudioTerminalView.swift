import AppKit
import GhosttyKit

/// Custom terminal view wrapping Ghostty's SurfaceView via SurfaceManager
/// Implements SurfaceContainer protocol for lifecycle management
final class AgentStudioTerminalView: NSView, SurfaceContainer, SurfaceHealthDelegate {
    let worktree: Worktree
    let repo: Repo

    // MARK: - SurfaceContainer Protocol

    private(set) var containerId: UUID
    var surfaceId: UUID?

    // MARK: - Private State

    private var ghosttySurface: Ghostty.SurfaceView?
    private(set) var isProcessRunning = false
    private var errorOverlay: SurfaceErrorOverlayView?
    /// Guards against re-entrant setup when an async Task is in flight.
    /// Set true before setup begins, cleared in setupTerminal() success/failure.
    private var isSettingUp = false

    /// The current terminal title
    var title: String {
        ghosttySurface?.title ?? worktree.name
    }

    /// Standard initializer - creates a new terminal surface
    init(worktree: Worktree, repo: Repo) {
        self.containerId = UUID()
        self.worktree = worktree
        self.repo = repo
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        // Note: Do NOT set wantsLayer or backgroundColor here
        // Let Ghostty manage its own layer rendering

        isSettingUp = true
        if SessionRegistry.shared.configuration.isOperational {
            // Session restore enabled: register + attach via tmux new-session -A
            Task { @MainActor in
                await setupTerminalWithSessionRestore()
            }
        } else {
            setupTerminal()
        }
    }

    /// Restoring initializer — defers terminal setup until the view is displayed.
    /// Used by the Codable decode path to avoid spawning orphaned processes.
    init(worktree: Worktree, repo: Repo, restoring: Bool, containerId: UUID = UUID()) {
        self.containerId = containerId
        self.worktree = worktree
        self.repo = repo
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        // Terminal setup is deferred to viewDidMoveToWindow
    }

    /// Restore initializer - for attaching an existing surface (undo close)
    /// Does NOT create a new surface; caller must attach one via displaySurface()
    init(worktree: Worktree, repo: Repo, restoredSurfaceId: UUID) {
        self.containerId = UUID()
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
        // Detach surface on dealloc (will go to undo stack)
        if let surfaceId = surfaceId {
            Task { @MainActor in
                SurfaceManager.shared.detach(surfaceId, reason: .close)
            }
        }
    }

    // MARK: - Terminal Setup

    /// Register pane session for tracking, then let the surface handle create+attach
    /// via `tmux new-session -A` (creates if missing, attaches if exists).
    private func setupTerminalWithSessionRestore() async {
        let registry = SessionRegistry.shared
        let sessionId = TmuxBackend.sessionId(projectId: repo.id, worktreeId: worktree.id, paneId: containerId)

        // Register session for health tracking (surface handles actual tmux creation)
        registry.registerPaneSession(
            id: sessionId,
            projectId: repo.id,
            worktreeId: worktree.id,
            displayName: worktree.name,
            workingDirectory: worktree.path
        )

        // Let the surface handle create+attach via new-session -A
        guard let attachCmd = registry.attachCommand(for: worktree, in: repo, paneId: containerId) else {
            ghosttyLogger.error("Session registered but attachCommand returned nil for \(sessionId)")
            setupTerminal()  // safety fallback
            return
        }
        setupTerminal(command: attachCmd)
    }

    private func setupTerminal(command: String? = nil) {
        let cmd = command ?? "\(getDefaultShell()) -i -l"

        let config = Ghostty.SurfaceConfiguration(
            workingDirectory: worktree.path.path,
            command: cmd
        )

        let metadata = SurfaceMetadata(
            workingDirectory: worktree.path,
            command: cmd,
            title: worktree.name,
            worktreeId: worktree.id,
            repoId: repo.id
        )

        // Create surface via manager
        let result = SurfaceManager.shared.createSurface(config: config, metadata: metadata)

        switch result {
        case .success(let managed):
            self.surfaceId = managed.id

            // Attach to this container
            SurfaceManager.shared.attach(managed.id, to: containerId)

            // Display the surface
            displaySurface(managed.surface)

            // Register for health updates
            SurfaceManager.shared.addHealthDelegate(self)

            self.isProcessRunning = true
            self.isSettingUp = false
            ghosttyLogger.info("Terminal created via SurfaceManager for worktree: \(self.worktree.name)")

        case .failure(let error):
            self.isSettingUp = false
            ghosttyLogger.error("Failed to create terminal: \(error.localizedDescription)")
            showGhosttyError(error)
        }
    }

    // MARK: - SurfaceContainer Protocol

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

        // Create new surface — route through session restore when available
        isSettingUp = true
        if SessionRegistry.shared.configuration.isOperational {
            Task { @MainActor in
                await setupTerminalWithSessionRestore()
            }
        } else {
            setupTerminal()
        }
        hideErrorOverlay()
    }

    // MARK: - Surface Close Handling

    @objc private func handleSurfaceClose(_ notification: Notification) {
        // Only notify if we weren't manually terminated
        guard isProcessRunning else { return }
        isProcessRunning = false
        handleProcessTerminated(exitCode: 0)
    }

    // MARK: - Shell Environment

    private func getDefaultShell() -> String {
        if let pw = getpwuid(getuid()), let shell = pw.pointee.pw_shell {
            return String(cString: shell)
        }
        if let envShell = ProcessInfo.processInfo.environment["SHELL"] {
            return envShell
        }
        return "/bin/zsh"
    }

    // MARK: - Error Handling

    private func showGhosttyError(_ error: Error? = nil) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Terminal Initialization Failed"
            alert.informativeText = error?.localizedDescription ?? "Failed to initialize the Ghostty terminal engine."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
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

    /// Request to close the terminal
    func requestClose() {
        guard let surfaceId = surfaceId else { return }

        // Detach from manager (goes to undo stack)
        SurfaceManager.shared.detach(surfaceId, reason: .close)

        // Notify termination
        handleProcessTerminated(exitCode: nil)
    }

    /// Terminate the terminal process (hard close, no undo)
    func terminateProcess() {
        guard isProcessRunning, let surfaceId = surfaceId else { return }
        isProcessRunning = false

        // Destroy immediately (no undo)
        SurfaceManager.shared.destroy(surfaceId)
        self.surfaceId = nil
    }

    /// Check if process is still running
    var processExited: Bool {
        guard let surfaceId = surfaceId else { return true }
        return SurfaceManager.shared.hasProcessExited(surfaceId)
    }

    // MARK: - Deferred Setup

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Lazily set up terminal when the view enters a window for the first time.
        // This handles restored views that deferred setupTerminal().
        if window != nil && surfaceId == nil && ghosttySurface == nil && !isSettingUp {
            if SessionRegistry.shared.configuration.isOperational {
                Task { @MainActor in
                    await setupTerminalWithSessionRestore()
                }
            } else {
                setupTerminal()
            }
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        // Ensure Ghostty surface knows its new size after split/resize.
        // Auto Layout propagates frame changes to the surface subview,
        // but this is a safety net for SwiftUI structural identity rebuilds.
        guard let surface = ghosttySurface, bounds.size.width > 0, bounds.size.height > 0 else { return }
        surface.sizeDidChange(surface.bounds.size)
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        if let surface = ghosttySurface, let window = window {
            // Set focus via SurfaceManager
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
        // If error overlay is showing, let it handle hits
        if let overlay = errorOverlay, !overlay.isHidden {
            let overlayPoint = convert(point, to: overlay)
            if overlay.bounds.contains(overlayPoint) {
                return overlay.hitTest(overlayPoint)
            }
        }

        // Otherwise pass to Ghostty surface
        if let surface = ghosttySurface, bounds.contains(point) {
            return surface
        }
        return super.hitTest(point)
    }

    // MARK: - SwiftUI Bridging

    /// Stable container for SwiftUI bridging.
    /// NSViewRepresentable returns this instead of creating new containers.
    /// The terminal view is added once and never reparented,
    /// preventing IOSurface crashes when SwiftUI recreates views.
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
    var id: UUID { containerId }
}

// MARK: - Codable

extension AgentStudioTerminalView: Codable {
    private enum CodingKeys: String, CodingKey {
        case worktreeId
        case repoId
        case containerId
        case title
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let worktreeId = try container.decode(UUID.self, forKey: .worktreeId)
        let repoId = try container.decode(UUID.self, forKey: .repoId)
        let savedContainerId = try container.decode(UUID.self, forKey: .containerId)

        // Look up worktree and repo from SessionManager
        guard let repo = SessionManager.shared.repos.first(where: { $0.id == repoId }),
              let worktree = repo.worktrees.first(where: { $0.id == worktreeId }) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Could not find worktree \(worktreeId) or repo \(repoId)"
                )
            )
        }

        // Use the base NSView init — do NOT call self.init(worktree:repo:) which
        // spawns a shell process immediately. Terminal setup is deferred until the
        // view is displayed, preventing orphaned processes on restore.
        self.init(worktree: worktree, repo: repo, restoring: true, containerId: savedContainerId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(worktree.id, forKey: .worktreeId)
        try container.encode(repo.id, forKey: .repoId)
        try container.encode(containerId, forKey: .containerId)
        try container.encode(title, forKey: .title)
    }
}
