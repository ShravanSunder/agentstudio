import Foundation
import os.log

private let configLogger = Logger(subsystem: "com.agentstudio", category: "SessionConfiguration")

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
        // Search order: SPM resource bundle → app bundle → dev source tree → relative fallback
        var candidates: [String] = []

        // 1. SPM resource bundle (AgentStudio_AgentStudio.bundle, adjacent to executable)
        let spmBundle = Bundle.main.bundleURL
            .appendingPathComponent("AgentStudio_AgentStudio.bundle").path
        candidates.append(spmBundle + "/tmux/ghost.conf")

        // 2. App bundle via Bundle API
        if let bundled = Bundle.main.path(forResource: "ghost", ofType: "conf") {
            candidates.append(bundled)
        }

        // 3. App bundle explicit path (Contents/Resources/tmux/ghost.conf)
        if let bundleRes = Bundle.main.resourcePath {
            candidates.append(bundleRes + "/tmux/ghost.conf")
        }

        // 4. Development source tree (SPM .build/ layout)
        if let devResources = findDevResourcesDir() {
            candidates.append(devResources + "/tmux/ghost.conf")
        }

        // 5. Relative fallback (only works when launched from project root)
        candidates.append("Sources/AgentStudio/Resources/tmux/ghost.conf")

        let sourcePath: String
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            sourcePath = found
        } else {
            configLogger.error("ghost.conf not found in any search path: \(candidates, privacy: .public)")
            sourcePath = candidates.last!
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
