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

    /// Directory for zmx socket/state isolation under the shared app data root.
    let zmxDir: String

    /// How often to run health checks on active sessions (seconds).
    let healthCheckInterval: TimeInterval

    /// Maximum checkpoint age before it's considered stale.
    let maxCheckpointAge: TimeInterval

    struct ZmxDiscoveryLocations: Sendable, Equatable {
        let bundledBinaryPath: String?
        let vendorBinaryPath: String?
        let wellKnownPaths: [String]

        static var defaults: Self {
            Self(
                bundledBinaryPath: Bundle.main.executableURL?
                    .deletingLastPathComponent()
                    .appendingPathComponent("zmx").path,
                vendorBinaryPath: SessionConfiguration.findDevVendorZmx(),
                wellKnownPaths: [
                    "/opt/homebrew/bin/zmx",
                    "/usr/local/bin/zmx",
                ]
            )
        }
    }

    // MARK: - Factory

    /// Detect configuration from the current environment.
    @concurrent
    static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        processExecutor: any ProcessExecutor = DefaultProcessExecutor(timeout: 2),
        discoveryLocations: ZmxDiscoveryLocations = .defaults
    ) async -> Self {
        guard isSessionRestoreEnabled(environment: environment) else {
            return resolved(environment: environment, zmxPath: nil)
        }
        let zmxPath = await findZmx(processExecutor: processExecutor, discoveryLocations: discoveryLocations)
        return resolved(environment: environment, zmxPath: zmxPath)
    }

    /// Build configuration from already-resolved process facts.
    static func resolved(environment: [String: String], zmxPath: String?) -> Self {
        let env = environment

        let isEnabled = isSessionRestoreEnabled(environment: env)

        let zmxDir = AppDataPaths.zmxDirectory(environment: env).path
        let healthInterval =
            env["AGENTSTUDIO_HEALTH_INTERVAL"]
            .flatMap { Double($0) }
            ?? 30.0

        RestoreTrace.log(
            "SessionConfiguration.detect enabled=\(isEnabled) zmxPath=\(zmxPath ?? "nil") zmxDir=\(zmxDir) healthInterval=\(healthInterval)"
        )

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

    init(
        isEnabled: Bool,
        zmxPath: String?,
        zmxDir: String,
        healthCheckInterval: TimeInterval,
        maxCheckpointAge: TimeInterval
    ) {
        self.isEnabled = isEnabled
        self.zmxPath = zmxPath
        self.zmxDir = zmxDir
        self.healthCheckInterval = healthCheckInterval
        self.maxCheckpointAge = maxCheckpointAge
    }

    /// Hidden/background panes restore only when a live zmx session already exists.
    func shouldRestoreHiddenPane(hasExistingSession: Bool) -> Bool {
        hasExistingSession
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
        let moduleBundle = Bundle.appResources.bundlePath
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
        let moduleTerminfo = Bundle.appResources.bundlePath + "/terminfo"
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

    private static func isSessionRestoreEnabled(environment: [String: String]) -> Bool {
        environment["AGENTSTUDIO_SESSION_RESTORE"]
            .map { $0.lowercased() == "true" || $0 == "1" }
            ?? true
    }

    /// Find the zmx binary.
    /// Fallback chain: bundled binary → vendor build output → well-known PATH → `which zmx`.
    /// Only the bundled candidate is launched during startup discovery; other candidates
    /// are treated as executable path facts so a bad user PATH cannot block app launch.
    private static func findZmx(
        processExecutor: any ProcessExecutor,
        discoveryLocations: ZmxDiscoveryLocations
    ) async -> String? {
        // 1. Bundled binary: same directory as the app executable (Contents/MacOS/zmx or .build/debug/zmx)
        if let bundled = discoveryLocations.bundledBinaryPath {
            if await isUsableZmxBinary(bundled, processExecutor: processExecutor) {
                return bundled
            }
            RestoreTrace.log("findZmx skip unusable bundled candidate=\(bundled)")
        }

        // 2. Vendor build output: for dev builds where zmx was built but not copied
        if let vendorBin = discoveryLocations.vendorBinaryPath,
            isExecutableZmxCandidate(vendorBin)
        {
            return vendorBin
        }

        // 3. Well-known PATH locations
        for candidate in discoveryLocations.wellKnownPaths {
            if isExecutableZmxCandidate(candidate) {
                return candidate
            }
        }

        // 4. Fallback: check PATH via which
        do {
            let result = try await processExecutor.execute(
                command: "/usr/bin/which",
                args: ["zmx"],
                cwd: nil,
                environment: nil
            )
            guard result.succeeded else { return nil }
            let path = result.stdout.trimmedNonEmpty
            if let path, !path.isEmpty,
                isExecutableZmxCandidate(path)
            {
                return path
            }
        } catch {
            // which not available or failed
            configLogger.warning("which zmx failed during detection: \(error.localizedDescription)")
        }
        return nil
    }

    private static func isExecutableZmxCandidate(_ candidatePath: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: candidatePath)
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

    /// Validate that a candidate zmx binary can actually launch and respond.
    private static func isUsableZmxBinary(
        _ candidatePath: String,
        processExecutor: any ProcessExecutor
    ) async -> Bool {
        guard FileManager.default.isExecutableFile(atPath: candidatePath) else { return false }

        do {
            let result = try await processExecutor.execute(
                command: candidatePath,
                args: ["--version"],
                cwd: nil,
                environment: nil
            )
            guard result.succeeded else {
                configLogger.warning(
                    "zmx candidate probe failed: \(candidatePath) exit=\(result.exitCode)"
                )
                return false
            }
            return true
        } catch {
            configLogger.warning("zmx candidate failed to launch: \(candidatePath) error=\(error.localizedDescription)")
            return false
        }
    }
}
