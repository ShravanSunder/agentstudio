import Foundation
import os.log

private let configLogger = Logger(subsystem: "com.agentstudio", category: "SessionConfiguration")

/// Configuration for the session restore feature.
/// Reads from environment variables with sensible defaults.
struct SessionConfiguration: Sendable {
    /// Whether session restore is enabled. Defaults to true.
    let isEnabled: Bool

    /// Path to the zmx binary. Nil if zmx is not found.
    let zmxPath: String?

    /// Directory for zmx socket/state isolation (~/.agentstudio/zmx/).
    let zmxDir: String

    /// How often to run health checks on active sessions (seconds).
    let healthCheckInterval: TimeInterval

    /// Maximum checkpoint age before it's considered stale.
    let maxCheckpointAge: TimeInterval

    // MARK: - Factory

    /// Detect configuration from the current environment.
    static func detect(environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        let env = environment

        let isEnabled =
            env["AGENTSTUDIO_SESSION_RESTORE"]
            .map { $0.lowercased() == "true" || $0 == "1" }
            ?? true

        let zmxPath = findZmx()
        let zmxDir = ZmxBackend.defaultZmxDir

        let healthInterval =
            env["AGENTSTUDIO_HEALTH_INTERVAL"]
            .flatMap { Double($0) }
            ?? 30.0

        return Self(
            isEnabled: isEnabled,
            zmxPath: zmxPath,
            zmxDir: zmxDir,
            healthCheckInterval: healthInterval,
            maxCheckpointAge: 7 * 24 * 60 * 60  // 1 week
        )
    }

    /// Whether session restore can actually work (enabled + zmx found).
    var isOperational: Bool {
        isEnabled && zmxPath != nil
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

        // SPM module bundle (works in both app and test contexts)
        let moduleBundle = Bundle.module.bundlePath
        if FileManager.default.fileExists(atPath: moduleBundle + sentinel) {
            return moduleBundle + "/ghostty"
        }

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
    /// Search order: module bundle → SPM resource bundle → app bundle → development source tree.
    static func resolveTerminfoDir() -> String? {
        let sentinel = "/78/xterm-256color"

        // SPM module bundle (works in both app and test contexts)
        let moduleTerminfo = Bundle.module.bundlePath + "/terminfo"
        if FileManager.default.fileExists(atPath: moduleTerminfo + sentinel) {
            return moduleTerminfo
        }

        // SPM resource bundle (adjacent to executable)
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

    // MARK: - Shell Discovery

    /// Resolve the user's default login shell.
    /// Checks passwd entry first, then SHELL environment variable, then falls back to /bin/zsh.
    static func defaultShell() -> String {
        if let pw = getpwuid(getuid()), let shell = pw.pointee.pw_shell {
            return String(cString: shell)
        }
        if let envShell = ProcessInfo.processInfo.environment["SHELL"] {
            return envShell
        }
        return "/bin/zsh"
    }

    // MARK: - Private

    /// Find the zmx binary.
    /// Fallback chain: bundled binary → vendor build output → well-known PATH → `which zmx`.
    private static func findZmx() -> String? {
        // 1. Bundled binary: same directory as the app executable (Contents/MacOS/zmx or .build/debug/zmx)
        if let bundled = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("zmx").path,
            FileManager.default.isExecutableFile(atPath: bundled)
        {
            return bundled
        }

        // 2. Vendor build output: for dev builds where zmx was built but not copied
        if let vendorBin = findDevVendorZmx() {
            return vendorBin
        }

        // 3. Well-known PATH locations
        let candidates = [
            "/opt/homebrew/bin/zmx",
            "/usr/local/bin/zmx",
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }

        // 4. Fallback: check PATH via which
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["zmx"]
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

    /// Find zmx in the vendor build output for development builds.
    /// Walks up from the executable to find `vendor/zmx/zig-out/bin/zmx`.
    private static func findDevVendorZmx() -> String? {
        var dir = URL(fileURLWithPath: Bundle.main.bundlePath)
        for _ in 0..<5 {
            dir = dir.deletingLastPathComponent()
            let candidate = dir.appendingPathComponent("vendor/zmx/zig-out/bin/zmx").path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
