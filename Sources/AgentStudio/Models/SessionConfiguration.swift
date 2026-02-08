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
    static func detect() -> SessionConfiguration {
        let env = ProcessInfo.processInfo.environment

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

    /// Find the bundled resources directory containing terminfo/.
    /// GHOSTTY_RESOURCES_DIR expects the parent of terminfo/.
    /// Checks app bundle first, then development source tree.
    static func resolveTerminfoDir() -> String? {
        // App bundle: Contents/Resources/terminfo/78/xterm-ghostty
        if let bundled = Bundle.main.resourcePath {
            let sentinel = bundled + "/terminfo/78/xterm-ghostty"
            if FileManager.default.fileExists(atPath: sentinel) {
                return bundled
            }
        }

        // Development (SPM): walk up from executable to find source tree
        if let devResources = findDevResourcesDir() {
            let sentinel = devResources + "/terminfo/78/xterm-ghostty"
            if FileManager.default.fileExists(atPath: sentinel) {
                return devResources
            }
        }

        return nil
    }

    // MARK: - Private

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
        // Look for ghost.conf in the app bundle first, then fallback to source tree
        if let bundled = Bundle.main.path(forResource: "ghost", ofType: "conf") {
            return bundled
        }

        // Development: walk up from executable to find source tree
        if let devResources = findDevResourcesDir() {
            let candidate = devResources + "/tmux/ghost.conf"
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        // Last resort: relative path (works if CWD is project root)
        return "Sources/AgentStudio/Resources/tmux/ghost.conf"
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
