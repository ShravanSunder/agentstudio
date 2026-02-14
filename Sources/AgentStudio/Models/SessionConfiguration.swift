import Foundation

/// Configuration for the session restore feature.
/// Reads from environment variables with sensible defaults.
struct SessionConfiguration: Sendable {
    /// Whether session restore is enabled. Defaults to false (opt-in).
    let isEnabled: Bool

    /// Path to the tmux binary. Nil if tmux is not found.
    let tmuxPath: String?

    /// Path to the ghost tmux config bundled with the app.
    let ghostConfigPath: String

    /// How often to run health checks on active sessions (seconds).
    let healthCheckInterval: TimeInterval

    /// tmux socket directory.
    let socketDirectory: String

    /// Custom tmux socket name for ghost sessions.
    let socketName: String

    /// Maximum checkpoint age before it's considered stale.
    let maxCheckpointAge: TimeInterval

    // MARK: - Factory

    /// Detect configuration from the current environment.
    static func detect(environment: [String: String] = ProcessInfo.processInfo.environment) -> SessionConfiguration {
        let env = environment

        let isEnabled = env["AGENTSTUDIO_SESSION_RESTORE"]
            .map { $0.lowercased() == "true" || $0 == "1" }
            ?? true

        let tmuxPath = findTmux()
        let ghostConfigPath = resolveGhostConfigPath()
        let socketDir = env["TMUX_TMPDIR"] ?? "/tmp/tmux-\(getuid())"

        let healthInterval = env["AGENTSTUDIO_HEALTH_INTERVAL"]
            .flatMap { Double($0) }
            ?? 30.0

        return SessionConfiguration(
            isEnabled: isEnabled,
            tmuxPath: tmuxPath,
            ghostConfigPath: ghostConfigPath,
            healthCheckInterval: healthInterval,
            socketDirectory: socketDir,
            socketName: TmuxBackend.socketName,
            maxCheckpointAge: 7 * 24 * 60 * 60  // 1 week
        )
    }

    /// Whether session restore can actually work (enabled + tmux found).
    var isOperational: Bool {
        isEnabled && tmuxPath != nil
    }

    // MARK: - Terminfo Discovery

    /// Resolve GHOSTTY_RESOURCES_DIR for GhosttyKit.
    ///
    /// GhosttyKit computes `TERMINFO = dirname(GHOSTTY_RESOURCES_DIR) + "/terminfo"`,
    /// so the value must be a subdirectory (e.g. `.../ghostty`) whose parent contains
    /// the `terminfo/` directory. We append `/ghostty` to the directory that holds
    /// `terminfo/` to satisfy this convention.
    ///
    /// Search order: SPM resource bundle → app bundle → development source tree.
    static func resolveGhosttyResourcesDir() -> String? {
        let sentinel = "/terminfo/78/xterm-ghostty"

        // SPM resource bundle (AgentStudio_AgentStudio.bundle, adjacent to executable)
        let spmBundle = Bundle.main.bundleURL
            .appendingPathComponent("AgentStudio_AgentStudio.bundle").path
        if FileManager.default.fileExists(atPath: spmBundle + sentinel) {
            return spmBundle + "/ghostty"
        }

        // App bundle: Contents/Resources/terminfo/78/xterm-ghostty
        if let bundled = Bundle.main.resourcePath {
            if FileManager.default.fileExists(atPath: bundled + sentinel) {
                return bundled + "/ghostty"
            }
        }

        // Development (SPM): walk up from executable to find source tree
        if let devResources = findDevResourcesDir() {
            if FileManager.default.fileExists(atPath: devResources + sentinel) {
                return devResources + "/ghostty"
            }
        }

        return nil
    }

    /// Resolve the terminfo directory containing our custom xterm-256color.
    ///
    /// This is the directory that should be set as TERMINFO inside tmux sessions
    /// so that programs find our custom xterm-256color (with SGR mouse, RGB, etc.)
    /// instead of the system xterm-256color. The tmux server persists across app
    /// restarts, so its initial TERMINFO may be stale; this path is injected at
    /// every attach to keep it current.
    ///
    /// Search order: SPM resource bundle → app bundle → development source tree.
    static func resolveTerminfoDir() -> String? {
        let sentinel = "/78/xterm-256color"

        // SPM resource bundle
        let spmBundle = Bundle.main.bundleURL
            .appendingPathComponent("AgentStudio_AgentStudio.bundle/terminfo").path
        if FileManager.default.fileExists(atPath: spmBundle + sentinel) {
            return spmBundle
        }

        // App bundle
        if let bundled = Bundle.main.resourcePath {
            let candidate = bundled + "/terminfo"
            if FileManager.default.fileExists(atPath: candidate + sentinel) {
                return candidate
            }
        }

        // Development source tree
        if let devResources = findDevResourcesDir() {
            let candidate = devResources + "/terminfo"
            if FileManager.default.fileExists(atPath: candidate + sentinel) {
                return candidate
            }
        }

        return nil
    }

    /// The safe terminfo directory at ~/.agentstudio/terminfo/.
    /// Used by both ghost.conf injection and the attach command's set-environment.
    /// This path avoids "AgentStudio" (mixed case) in the tmux command line.
    static var safeTerminfoPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agentstudio/terminfo").path
    }

    // MARK: - Private

    /// Copy the custom terminfo to ~/.agentstudio/terminfo/ (pkill-safe path).
    /// Returns the safe directory path, or nil if the copy fails.
    private static func copySafeTerminfo() -> String? {
        guard let sourceDir = resolveTerminfoDir() else { return nil }

        let safeDir = URL(fileURLWithPath: safeTerminfoPath)
        let sourceFile = URL(fileURLWithPath: sourceDir + "/78/xterm-256color")
        let destDir = safeDir.appendingPathComponent("78")
        let destFile = destDir.appendingPathComponent("xterm-256color")

        guard FileManager.default.fileExists(atPath: sourceFile.path) else { return nil }

        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destFile.path) {
                try FileManager.default.removeItem(at: destFile)
            }
            try FileManager.default.copyItem(at: sourceFile, to: destFile)
            return safeDir.path
        } catch {
            return nil
        }
    }

    private static func findTmux() -> String? {
        // Check well-known locations first (faster than spawning a process)
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }

        // Fallback: check PATH via which
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["tmux"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {
            // which not available or failed
        }
        return nil
    }

    private static func resolveGhostConfigPath() -> String {
        // Find the source config (bundle or dev tree)
        let sourcePath: String
        if let bundled = Bundle.main.path(forResource: "ghost", ofType: "conf") {
            sourcePath = bundled
        } else if let devResources = findDevResourcesDir() {
            let candidate = devResources + "/tmux/ghost.conf"
            if FileManager.default.fileExists(atPath: candidate) {
                sourcePath = candidate
            } else {
                sourcePath = "Sources/AgentStudio/Resources/tmux/ghost.conf"
            }
        } else {
            sourcePath = "Sources/AgentStudio/Resources/tmux/ghost.conf"
        }

        // Copy to ~/.agentstudio/tmux/ghost.conf so the tmux server's command
        // line doesn't contain "AgentStudio". Without this, `pkill -f AgentStudio`
        // kills the tmux server (whose -f flag embeds the config path), destroying
        // all sessions that should survive app termination.
        let safeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agentstudio/tmux")
        let safePath = safeDir.appendingPathComponent("ghost.conf")

        do {
            try FileManager.default.createDirectory(at: safeDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: safePath.path) {
                try FileManager.default.removeItem(at: safePath)
            }
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: sourcePath),
                to: safePath
            )

            // Copy terminfo to ~/.agentstudio/terminfo/ and inject the safe path
            // into ghost.conf. This ensures:
            // 1. Programs inside tmux find our custom xterm-256color (SGR mouse, RGB)
            // 2. The tmux command line doesn't contain "AgentStudio" (pkill safety)
            // 3. The tmux server picks up the correct TERMINFO even after restart
            if let safeTerminfo = copySafeTerminfo() {
                let terminfoLine = "\n# ─── Runtime TERMINFO (injected by Agent Studio at launch) ────────\n"
                    + "set-environment -g TERMINFO \"\(safeTerminfo)\"\n"
                let handle = try FileHandle(forWritingTo: safePath)
                handle.seekToEndOfFile()
                handle.write(terminfoLine.data(using: .utf8)!)
                handle.closeFile()
            }

            return safePath.path
        } catch {
            return sourcePath
        }
    }

    /// Walk up from the executable directory looking for the dev source tree.
    /// For SPM builds, Bundle.main.bundlePath is e.g. `.build/release/` —
    /// we need to find the project root containing `Sources/AgentStudio/Resources/`.
    private static func findDevResourcesDir() -> String? {
        var dir = URL(fileURLWithPath: Bundle.main.bundlePath)
        for _ in 0..<5 {
            dir = dir.deletingLastPathComponent()
            let candidate = dir.appendingPathComponent("Sources/AgentStudio/Resources")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }
        return nil
    }
}
