import AppKit
import GhosttyKit

/// Custom terminal view wrapping Ghostty's SurfaceView with Zellij integration
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

        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0).cgColor

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

        // Create Zellij command
        let sessionName = worktree.zellijSessionName(projectName: project.name)
        let zellijPath = findZellij()

        guard FileManager.default.isExecutableFile(atPath: zellijPath) else {
            showZellijNotFoundError()
            return
        }

        // Create the command to run in the terminal
        // We'll use the shell to run Zellij with proper environment
        let shell = getDefaultShell()
        let zellijCommand = "cd '\(worktree.path.path)' && exec '\(zellijPath)' attach --create '\(sessionName)'"

        // Create surface configuration
        let config = Ghostty.SurfaceConfiguration(
            workingDirectory: worktree.path.path,
            command: "\(shell) -i -l -c \"\(zellijCommand)\""
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

    private func findZellij() -> String {
        let paths = [
            "/opt/homebrew/bin/zellij",
            "/usr/local/bin/zellij",
            "/run/current-system/sw/bin/zellij",
            "\(NSHomeDirectory())/.nix-profile/bin/zellij",
            "\(NSHomeDirectory())/.cargo/bin/zellij",
            "/usr/bin/zellij"
        ]

        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return "/opt/homebrew/bin/zellij"
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

    private func showZellijNotFoundError() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Zellij Not Found"
            alert.informativeText = "Zellij is required for AgentStudio terminals.\n\nInstall with: brew install zellij"
            alert.alertStyle = .warning
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

    /// Detach from Zellij session (preserves session for later reattach)
    func detachFromZellij() {
        guard isProcessRunning, let surface = ghosttySurface else { return }
        // Send Ctrl-O d to detach from Zellij
        surface.sendText("\u{0F}d")
    }

    /// Terminate the terminal process
    func terminateProcess() {
        guard isProcessRunning else { return }
        ghosttySurface?.requestClose()
        isProcessRunning = false
    }

    /// Check if process is still running
    var processExited: Bool {
        ghosttySurface?.processExited ?? true
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        if let surface = ghosttySurface {
            window?.makeFirstResponder(surface)
            return true
        }
        return super.becomeFirstResponder()
    }
}
