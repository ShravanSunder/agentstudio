// SessionConfiguration.swift
// AgentStudio
//
// Central configuration for Zellij session management.
// Session restore is either enabled (requires Zellij) or disabled entirely.

import Foundation
import OSLog

// MARK: - Session Configuration

/// Central configuration for Zellij session management.
///
/// Session restore has two modes:
/// - **Enabled**: Zellij is required. Sessions persist across app restarts.
/// - **Disabled**: No session management. Each terminal is independent.
///
/// Configuration priority: Environment variables > User settings > Defaults
@MainActor
@Observable
final class SessionConfiguration: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = SessionConfiguration()

    // MARK: - Environment Variable Keys

    private enum EnvKey {
        /// Enable/disable session restore (true/false/1/0)
        static let restore = "AGENTSTUDIO_SESSION_RESTORE"
        /// Custom path to Zellij binary
        static let zellijPath = "AGENTSTUDIO_ZELLIJ_PATH"
        /// Zellij's socket directory (mirrors Zellij's own env var)
        static let socketDir = "ZELLIJ_SOCK_DIR"
        /// XDG runtime directory (standard on Linux)
        static let xdgRuntimeDir = "XDG_RUNTIME_DIR"
        /// Health check interval in seconds
        static let healthCheckInterval = "AGENTSTUDIO_HEALTH_CHECK_INTERVAL"
    }

    // MARK: - User Defaults Keys

    private enum DefaultsKey {
        static let restore = "sessionRestoreEnabled"
        static let zellijPath = "zellijPath"
        static let healthCheckInterval = "healthCheckInterval"
    }

    // MARK: - Defaults

    private enum Defaults {
        static let healthCheckInterval: TimeInterval = 30.0
        static let restoreEnabled = true
    }

    // MARK: - Logger

    private let logger = Logger(subsystem: "AgentStudio", category: "SessionConfiguration")

    // MARK: - Detection Results

    /// Whether Zellij is available on this system.
    private(set) var zellijAvailable: Bool = false

    /// Detected Zellij version string.
    private(set) var zellijVersion: String?

    /// Detected socket directory from Zellij.
    private(set) var detectedSocketDir: URL?

    /// Whether detection has been performed.
    private(set) var detectionComplete: Bool = false

    // MARK: - Computed Configuration

    /// Whether session restore is enabled.
    /// When enabled, Zellij is required. When disabled, no session management occurs.
    var sessionRestoreEnabled: Bool {
        // 1. Environment variable (highest priority)
        if let envValue = env(EnvKey.restore) {
            let enabled = envValue.lowercased() == "true" || envValue == "1"
            // If enabled via env var but Zellij not available, log warning
            if enabled && detectionComplete && !zellijAvailable {
                logger.warning("Session restore enabled via env var but Zellij not available")
            }
            return enabled && zellijAvailable
        }

        // 2. User setting
        if UserDefaults.standard.object(forKey: DefaultsKey.restore) != nil {
            let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.restore)
            return enabled && zellijAvailable
        }

        // 3. Default: enabled if Zellij is available
        return zellijAvailable && Defaults.restoreEnabled
    }

    /// Path to Zellij binary.
    var zellijPath: String {
        // 1. Environment variable
        if let envValue = env(EnvKey.zellijPath), !envValue.isEmpty {
            return envValue
        }

        // 2. User setting
        if let stored = UserDefaults.standard.string(forKey: DefaultsKey.zellijPath),
           !stored.isEmpty {
            return stored
        }

        // 3. Default: rely on PATH
        return "zellij"
    }

    /// Zellij socket directory.
    /// Mirrors Zellij's own socket directory discovery logic.
    var socketDir: URL {
        // 1. Use detected socket dir from Zellij if available
        if let detected = detectedSocketDir {
            return detected
        }

        // 2. ZELLIJ_SOCK_DIR env var (same as Zellij uses)
        if let envValue = env(EnvKey.socketDir), !envValue.isEmpty {
            return URL(fileURLWithPath: envValue)
        }

        // 3. XDG_RUNTIME_DIR/zellij (Linux standard)
        if let xdgRuntime = env(EnvKey.xdgRuntimeDir), !xdgRuntime.isEmpty {
            return URL(fileURLWithPath: xdgRuntime).appendingPathComponent("zellij")
        }

        // 4. Fallback: /tmp/zellij-{uid}/ (Zellij's default)
        let uid = getuid()
        return URL(fileURLWithPath: "/tmp/zellij-\(uid)")
    }

    /// Health check interval in seconds.
    var healthCheckInterval: TimeInterval {
        // 1. Environment variable
        if let envValue = env(EnvKey.healthCheckInterval),
           let interval = TimeInterval(envValue), interval > 0 {
            return interval
        }

        // 2. User setting
        let stored = UserDefaults.standard.double(forKey: DefaultsKey.healthCheckInterval)
        if stored > 0 {
            return stored
        }

        // 3. Default
        return Defaults.healthCheckInterval
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Detection

    /// Detect Zellij availability and configuration. Call once at startup.
    func detectZellij() async {
        guard !detectionComplete else { return }

        logger.info("Detecting Zellij...")

        // Step 1: Check if Zellij is available and get version
        let versionResult = await runZellijCommand(["--version"])

        if versionResult.succeeded {
            zellijVersion = versionResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            zellijAvailable = true
            logger.info("Zellij detected: \(self.zellijVersion ?? "unknown")")

            // Step 2: Detect socket directory using setup --check
            await detectSocketDirectory()
        } else {
            zellijAvailable = false
            logger.info("Zellij not available")
        }

        detectionComplete = true
    }

    /// Detect socket directory by querying Zellij's setup.
    private func detectSocketDirectory() async {
        // Method 1: Try to get socket dir from Zellij setup --check
        // This outputs configuration info including socket directory
        let setupResult = await runZellijCommand(["setup", "--check"])

        if setupResult.succeeded {
            // Parse output for socket directory info
            // Format varies by version, look for common patterns
            let output = setupResult.output

            // Look for "ZELLIJ_SOCK_DIR" or socket-related info
            if let socketLine = output.components(separatedBy: .newlines)
                .first(where: { $0.contains("socket") || $0.contains("SOCK_DIR") }) {
                // Extract path from the line
                if let pathMatch = socketLine.range(of: "/[^\\s]+", options: .regularExpression) {
                    let path = String(socketLine[pathMatch])
                    detectedSocketDir = URL(fileURLWithPath: path)
                    logger.info("Detected socket directory: \(path)")
                    return
                }
            }
        }

        // Method 2: Check if socket directory exists at expected locations
        let candidates = [
            env(EnvKey.socketDir).map { URL(fileURLWithPath: $0) },
            env(EnvKey.xdgRuntimeDir).map { URL(fileURLWithPath: $0).appendingPathComponent("zellij") },
            URL(fileURLWithPath: "/tmp/zellij-\(getuid())")
        ].compactMap { $0 }

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                detectedSocketDir = candidate
                logger.info("Found socket directory: \(candidate.path)")
                return
            }
        }

        // Method 3: Create a test session to discover socket dir
        // This is more invasive but guaranteed to work
        let listResult = await runZellijCommand(["list-sessions"])
        if listResult.succeeded {
            // If list-sessions works, Zellij has created its socket dir
            // Re-check the candidates
            for candidate in candidates {
                if FileManager.default.fileExists(atPath: candidate.path) {
                    detectedSocketDir = candidate
                    logger.info("Found socket directory after list-sessions: \(candidate.path)")
                    return
                }
            }
        }

        logger.info("Using default socket directory: \(self.socketDir.path)")
    }

    /// Run a Zellij command and return the result.
    private func runZellijCommand(_ arguments: [String]) async -> (succeeded: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [zellijPath] + arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            return (process.terminationStatus == 0, output)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// Reset detection state (for testing).
    func resetDetection() {
        detectionComplete = false
        zellijAvailable = false
        zellijVersion = nil
        detectedSocketDir = nil
    }

    // MARK: - Setters (for UI preferences)

    /// Set whether session restore is enabled.
    func setSessionRestoreEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.restore)
        logger.info("Session restore enabled: \(enabled)")
    }

    /// Set custom Zellij path.
    func setZellijPath(_ path: String?) {
        if let path = path, !path.isEmpty {
            UserDefaults.standard.set(path, forKey: DefaultsKey.zellijPath)
            logger.info("Zellij path set to: \(path)")
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.zellijPath)
            logger.info("Zellij path reset to default")
        }
        // Reset detection since path changed
        resetDetection()
    }

    /// Set health check interval.
    func setHealthCheckInterval(_ interval: TimeInterval) {
        guard interval > 0 else { return }
        UserDefaults.standard.set(interval, forKey: DefaultsKey.healthCheckInterval)
        logger.info("Health check interval set to: \(interval)s")
    }

    // MARK: - Validation

    /// Validate current configuration and return any errors.
    func validate() -> [ConfigurationError] {
        var errors: [ConfigurationError] = []

        // If restore is explicitly requested but Zellij not available
        if let envValue = env(EnvKey.restore),
           (envValue.lowercased() == "true" || envValue == "1"),
           !zellijAvailable {
            errors.append(.zellijNotAvailable(
                "Session restore enabled but Zellij not found at: \(zellijPath)"
            ))
        }

        return errors
    }

    // MARK: - Helpers

    private func env(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }
}

// MARK: - Configuration Errors

/// Errors that can occur with session configuration.
enum ConfigurationError: Error, LocalizedError, Equatable {
    case zellijNotAvailable(String)
    case invalidSocketDir(String)

    var errorDescription: String? {
        switch self {
        case .zellijNotAvailable(let message):
            return "Zellij not available: \(message)"
        case .invalidSocketDir(let message):
            return "Invalid socket directory: \(message)"
        }
    }
}
