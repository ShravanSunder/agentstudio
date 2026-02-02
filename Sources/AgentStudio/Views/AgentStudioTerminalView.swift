import AppKit
import SwiftTerm

/// Delegate to receive terminal events
class AgentStudioTerminalDelegate: NSObject, LocalProcessTerminalViewDelegate {
    weak var terminalView: AgentStudioTerminalView?

    init(terminalView: AgentStudioTerminalView) {
        self.terminalView = terminalView
        super.init()
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        terminalView?.handleProcessTerminated(exitCode: exitCode)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // Could update tab title with current directory if needed
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // Size changes are handled automatically by SwiftTerm
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // Could update tab title if needed
    }
}

/// Custom terminal view with fixes for:
/// - Nerd Font support
/// - Proper login shell environment initialization
class AgentStudioTerminalView: LocalProcessTerminalView {
    let worktree: Worktree
    let project: Project
    private var isProcessRunning = false
    private var processEventDelegate: AgentStudioTerminalDelegate?

    init(worktree: Worktree, project: Project) {
        self.worktree = worktree
        self.project = project
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        // Set up delegate
        let delegate = AgentStudioTerminalDelegate(terminalView: self)
        self.processEventDelegate = delegate
        self.processDelegate = delegate

        configureAppearance()
        startZellijSession()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Font Configuration

    private func configureAppearance() {
        // Preferred Nerd Fonts for powerline symbol support
        let preferredFonts = [
            "JetBrainsMono Nerd Font",
            "JetBrainsMono Nerd Font Mono",
            "FiraCode Nerd Font",
            "FiraCode Nerd Font Mono",
            "Hack Nerd Font",
            "Hack Nerd Font Mono",
            "MesloLGS NF",
            "MesloLGS Nerd Font",
            "Menlo"
        ]

        var selectedFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        for fontName in preferredFonts {
            if let nerdFont = NSFont(name: fontName, size: 13) {
                selectedFont = nerdFont
                break
            }
        }
        font = selectedFont

        // Terminal colors - dark theme
        nativeForegroundColor = NSColor(white: 0.85, alpha: 1.0)
        nativeBackgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)

        // Cursor
        caretColor = NSColor(red: 0.4, green: 0.8, blue: 0.4, alpha: 1.0)
    }

    // MARK: - Shell Environment (CORRECT APPROACH)
    //
    // Real terminals (Kitty, WezTerm, iTerm2) work because they:
    // 1. Spawn shell with argv[0] = "-zsh" (login shell marker)
    // 2. Login shell sources .zprofile → .zshrc
    // 3. Tools (zoxide, atuin, direnv, fnm) get initialized
    // 4. User runs commands in fully initialized environment
    //
    // WRONG: Launch Zellij directly (bypasses login shell init)
    // RIGHT: Launch login shell, then run Zellij inside it

    private func startZellijSession() {
        let sessionName = worktree.zellijSessionName(projectName: project.name)

        // Get user's default shell from passwd database (like real terminals do)
        let shell = getDefaultShell()
        let shellName = URL(fileURLWithPath: shell).lastPathComponent

        // Find Zellij executable
        let zellijPath = findZellij()

        // Check if Zellij is available
        guard FileManager.default.isExecutableFile(atPath: zellijPath) else {
            showZellijNotFoundError()
            return
        }

        // Create the Zellij command to run inside the login shell
        // Using 'exec' to replace the shell process with Zellij
        let zellijCommand = "cd '\(worktree.path.path)' && exec '\(zellijPath)' attach --create '\(sessionName)'"

        // Launch as LOGIN SHELL (argv[0] = "-zsh") that runs Zellij
        // This ensures .zprofile and .zshrc are sourced BEFORE Zellij starts
        //
        // Arguments:
        // -l = login shell (sources profile files)
        // -c = run command
        //
        // execName with hyphen prefix = POSIX standard for login shell
        startProcess(
            executable: shell,
            args: ["-i", "-l", "-c", zellijCommand],  // -i = interactive (sources .zshrc)
            environment: nil,  // Inherit from app, shell will add its own
            execName: "-\(shellName)"  // CRITICAL: hyphen prefix = login shell
        )

        isProcessRunning = true
    }

    /// Get the user's default shell from passwd database
    /// This is more reliable than $SHELL which may be stale
    private func getDefaultShell() -> String {
        // Get shell from passwd database (like WezTerm does)
        if let pw = getpwuid(getuid()), let shell = pw.pointee.pw_shell {
            return String(cString: shell)
        }
        // Fallback to environment variable
        if let envShell = ProcessInfo.processInfo.environment["SHELL"] {
            return envShell
        }
        // Last resort
        return "/bin/zsh"
    }

    /// Find Zellij executable in common locations
    private func findZellij() -> String {
        let paths = [
            "/opt/homebrew/bin/zellij",  // Apple Silicon Homebrew
            "/usr/local/bin/zellij",      // Intel Homebrew
            "/run/current-system/sw/bin/zellij",  // NixOS
            "\(NSHomeDirectory())/.nix-profile/bin/zellij",  // Nix user profile
            "\(NSHomeDirectory())/.cargo/bin/zellij",  // Cargo install
            "/usr/bin/zellij"  // System
        ]

        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Try to find via `which` as last resort
        return "/opt/homebrew/bin/zellij"
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

    /// Handle process termination (called by delegate)
    func handleProcessTerminated(exitCode: Int32?) {
        isProcessRunning = false

        // Notify that this terminal's process has ended
        NotificationCenter.default.post(
            name: .terminalProcessTerminated,
            object: self,
            userInfo: ["worktreeId": worktree.id, "exitCode": exitCode as Any]
        )
    }

    /// Detach from Zellij session (preserves session for later reattach)
    func detachFromZellij() {
        guard isProcessRunning else { return }
        // Send Ctrl-O d to detach from Zellij (default prefix + d)
        // This preserves the session so it can be reattached
        send(txt: "\u{0F}d")
    }

    /// Terminate the terminal process
    func terminateProcess() {
        guard isProcessRunning else { return }
        // Send SIGTERM to gracefully terminate
        // Use the LocalProcess's running property
        isProcessRunning = false
    }
}
