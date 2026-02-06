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
            ?? false

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

        // Development (SPM): .build/release/../../Sources/AgentStudio/Resources/
        let devResources = Bundle.main.bundlePath + "/../Sources/AgentStudio/Resources"
        let devSentinel = devResources + "/terminfo/78/xterm-ghostty"
        if FileManager.default.fileExists(atPath: devSentinel) {
            return devResources
        }

        return nil
    }

    // MARK: - Private

    private static func findTmux() -> String? {
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func resolveGhostConfigPath() -> String {
        // Look for ghost.conf in the app bundle first, then fallback to source tree
        if let bundled = Bundle.main.path(forResource: "ghost", ofType: "conf") {
            return bundled
        }

        // Development fallback: relative to the binary
        let devPath = Bundle.main.bundlePath + "/../Sources/AgentStudio/Resources/tmux/ghost.conf"
        if FileManager.default.fileExists(atPath: devPath) {
            return devPath
        }

        // Last resort: known source location
        return "Sources/AgentStudio/Resources/tmux/ghost.conf"
    }
}
