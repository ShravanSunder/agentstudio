import Foundation
import SwiftTerm
import AppKit

/// Manages SwiftTerm terminal instances
@MainActor
final class TerminalManager: ObservableObject {
    static let shared = TerminalManager()

    // MARK: - State

    private var terminals: [UUID: LocalProcessTerminalView] = [:]
    private var terminalDelegates: [UUID: TerminalDelegate] = [:]

    // MARK: - Initialization

    private init() {}

    // MARK: - Terminal Management

    /// Create a terminal for a worktree
    func createTerminal(for worktree: Worktree, in project: Project) -> LocalProcessTerminalView {
        // Return existing if already created
        if let existing = terminals[worktree.id] {
            return existing
        }

        let terminal = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        // Configure appearance
        configureTerminalAppearance(terminal)

        // Set up delegate
        let delegate = TerminalDelegate(worktreeId: worktree.id, terminalManager: self)
        terminalDelegates[worktree.id] = delegate
        terminal.processDelegate = delegate

        // Derive zellij session name
        let sessionName = worktree.zellijSessionName(projectName: project.name)

        // Start zellij with attach --create
        // This will attach to existing session or create new one
        startZellijSession(terminal: terminal, sessionName: sessionName, workingDirectory: worktree.path)

        terminals[worktree.id] = terminal
        return terminal
    }

    /// Get existing terminal for a worktree
    func terminal(for worktreeId: UUID) -> LocalProcessTerminalView? {
        terminals[worktreeId]
    }

    /// Close terminal for a worktree
    func closeTerminal(for worktreeId: UUID) {
        guard let terminal = terminals[worktreeId] else { return }

        // Detach from zellij gracefully (Ctrl-O d)
        // This preserves the zellij session for later reattachment
        terminal.send(txt: "\u{0F}d")  // Ctrl-O d

        // Give it a moment, then clean up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.terminals.removeValue(forKey: worktreeId)
            self?.terminalDelegates.removeValue(forKey: worktreeId)
        }
    }

    /// Send command to a terminal
    func sendCommand(to worktreeId: UUID, command: String) {
        terminals[worktreeId]?.send(txt: command + "\n")
    }

    // MARK: - Zellij Integration

    /// Start zellij session in terminal
    private func startZellijSession(terminal: LocalProcessTerminalView, sessionName: String, workingDirectory: URL) {
        // Build environment with proper PATH
        var environment = ProcessInfo.processInfo.environment
        if let path = environment["PATH"] {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(path)"
        }

        // Set working directory
        environment["PWD"] = workingDirectory.path

        // Find zellij executable
        let zellijPath = findExecutable("zellij") ?? "/opt/homebrew/bin/zellij"

        // Convert environment dict to array of "KEY=VALUE" strings
        let envArray = environment.map { "\($0.key)=\($0.value)" }

        terminal.startProcess(
            executable: zellijPath,
            args: ["attach", "--create", sessionName],
            environment: envArray,
            execName: "zellij"
        )
    }

    /// Find executable in PATH
    private func findExecutable(_ name: String) -> String? {
        let searchPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin"
        ]

        for path in searchPaths {
            let fullPath = "\(path)/\(name)"
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }

        return nil
    }

    // MARK: - Terminal Appearance

    /// Configure terminal appearance (colors, font, etc.)
    private func configureTerminalAppearance(_ terminal: LocalProcessTerminalView) {
        // Font
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Colors - using a dark theme similar to VS Code Dark+
        terminal.nativeForegroundColor = NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0)
        terminal.nativeBackgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        terminal.caretColor = NSColor.white
        terminal.caretTextColor = NSColor.black

        // Selection color
        terminal.selectedTextBackgroundColor = NSColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.5)
    }

    // MARK: - Process Events

    /// Called when terminal process terminates
    func processTerminated(worktreeId: UUID, exitCode: Int32) {
        // Clean up
        terminals.removeValue(forKey: worktreeId)
        terminalDelegates.removeValue(forKey: worktreeId)

        // Post notification for UI to handle
        NotificationCenter.default.post(
            name: .terminalProcessTerminated,
            object: nil,
            userInfo: ["worktreeId": worktreeId, "exitCode": exitCode]
        )
    }
}

// MARK: - Terminal Delegate

/// Delegate for terminal process events
final class TerminalDelegate: NSObject, LocalProcessTerminalViewDelegate {
    let worktreeId: UUID
    weak var terminalManager: TerminalManager?

    init(worktreeId: UUID, terminalManager: TerminalManager) {
        self.worktreeId = worktreeId
        self.terminalManager = terminalManager
        super.init()
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // Terminal resized - zellij handles this automatically
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // Could update tab title if desired
    }

    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
        // Directory changed in terminal
    }

    func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            terminalManager?.processTerminated(worktreeId: worktreeId, exitCode: exitCode ?? -1)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let terminalProcessTerminated = Notification.Name("terminalProcessTerminated")
}
