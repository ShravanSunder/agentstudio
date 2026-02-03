import AppKit
import GhosttyKit

/// Custom terminal view wrapping Ghostty's SurfaceView
class AgentStudioTerminalView: NSView {
    let worktree: Worktree
    let project: Project
    private var ghosttySurface: Ghostty.SurfaceView?
    private var isProcessRunning = false
    private var titleObserver: NSKeyValueObservation?

    /// The current terminal title
    var title: String {
        ghosttySurface?.title ?? worktree.name
    }

    init(worktree: Worktree, project: Project) {
        self.worktree = worktree
        self.project = project
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        // Note: Do NOT set wantsLayer or backgroundColor here
        // Let Ghostty manage its own layer rendering
        setupGhosttyTerminal()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    deinit {
        titleObserver?.invalidate()
    }

    // MARK: - Ghostty Setup

    private func setupGhosttyTerminal() {
        guard let app = Ghostty.sharedApp else {
            ghosttyLogger.error("Cannot create terminal: Ghostty not initialized")
            showGhosttyError()
            return
        }

        // Start an interactive login shell in the worktree directory
        let shell = getDefaultShell()

        let config = Ghostty.SurfaceConfiguration(
            workingDirectory: worktree.path.path,
            command: "\(shell) -i -l"
        )

        // Create the Ghostty surface view
        let surface = Ghostty.SurfaceView(app: app, config: config)
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)

        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        self.ghosttySurface = surface
        self.isProcessRunning = true

        // Make this view layer-backed AFTER the surface is created
        // This ensures proper layer compositing with the child's IOSurfaceLayer
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor

        // Listen for surface close
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSurfaceClose(_:)),
            name: .ghosttyCloseSurface,
            object: surface
        )

        ghosttyLogger.info("Ghostty terminal created for worktree: \(self.worktree.name)")
    }

    @objc private func handleSurfaceClose(_ notification: Notification) {
        // Only notify if we weren't manually terminated (isProcessRunning would still be true)
        // When manually closed via terminateProcess(), isProcessRunning is set false BEFORE requestClose
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

    private func showGhosttyError() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Terminal Initialization Failed"
            alert.informativeText = "Failed to initialize the Ghostty terminal engine."
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

    /// Terminate the terminal process
    func terminateProcess() {
        guard isProcessRunning else { return }
        // Set flag BEFORE requestClose to prevent handleSurfaceClose from posting notification
        isProcessRunning = false
        ghosttySurface?.requestClose()
    }

    /// Check if process is still running
    var processExited: Bool {
        ghosttySurface?.processExited ?? true
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        if let surface = ghosttySurface, let window = window {
            return window.makeFirstResponder(surface)
        }
        return super.becomeFirstResponder()
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Always return the Ghostty surface for hit testing so it gets all mouse events
        if let surface = ghosttySurface, bounds.contains(point) {
            return surface
        }
        return super.hitTest(point)
    }
}
