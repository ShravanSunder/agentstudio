// SessionConfiguration.swift
// AgentStudio
//
// Central configuration for session management with environment variable
// and user settings support.

import Foundation
import OSLog

// MARK: - Backend Type

/// Session backend type for terminal multiplexing.
enum SessionBackendType: String, Codable, CaseIterable, Sendable {
    case zellij = "zellij"      // Full Zellij session management
    case none = "none"          // Direct shell, no multiplexer
    // Future: case tmux = "tmux"

    var displayName: String {
        switch self {
        case .zellij:
            return "Zellij (recommended)"
        case .none:
            return "None (basic shell)"
        }
    }

    var supportsRestore: Bool {
        switch self {
        case .zellij:
            return true
        case .none:
            return false
        }
    }

    var supportsTabs: Bool {
        switch self {
        case .zellij:
            return true
        case .none:
            return false
        }
    }
}

// MARK: - Session Configuration

/// Central configuration for session management.
/// Reads from environment variables (highest priority), user settings, and auto-detection.
@MainActor
@Observable
final class SessionConfiguration: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = SessionConfiguration()

    // MARK: - Environment Variable Keys

    private enum EnvKey {
        static let backend = "AGENTSTUDIO_SESSION_BACKEND"
        static let restore = "AGENTSTUDIO_SESSION_RESTORE"
        static let zellijPath = "AGENTSTUDIO_ZELLIJ_PATH"
        static let socketDir = "ZELLIJ_SOCK_DIR"
        static let healthCheckInterval = "AGENTSTUDIO_HEALTH_CHECK_INTERVAL"
    }

    // MARK: - User Defaults Keys

    private enum DefaultsKey {
        static let backend = "sessionBackend"
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

    // MARK: - Cached Detection Results

    /// Whether Zellij is available on this system.
    private(set) var zellijAvailable: Bool = false

    /// Detected Zellij version string.
    private(set) var zellijVersion: String?

    /// Whether detection has been performed.
    private(set) var detectionComplete: Bool = false

    // MARK: - Computed Configuration

    /// Effective backend type (env var > user setting > auto-detect).
    var backend: SessionBackendType {
        // 1. Environment variable (highest priority)
        if let envValue = env(EnvKey.backend),
           let type = SessionBackendType(rawValue: envValue.lowercased()) {
            return type
        }

        // 2. User setting
        if let stored = UserDefaults.standard.string(forKey: DefaultsKey.backend),
           let type = SessionBackendType(rawValue: stored) {
            return type
        }

        // 3. Auto-detect: use Zellij if available, otherwise none
        return zellijAvailable ? .zellij : .none
    }

    /// Whether session restore is enabled.
    var restoreEnabled: Bool {
        // 1. Environment variable (highest priority)
        if let envValue = env(EnvKey.restore) {
            return envValue.lowercased() == "true" || envValue == "1"
        }

        // 2. User setting
        if UserDefaults.standard.object(forKey: DefaultsKey.restore) != nil {
            return UserDefaults.standard.bool(forKey: DefaultsKey.restore)
        }

        // 3. Default: enabled only if backend supports it
        return backend.supportsRestore && Defaults.restoreEnabled
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
    var socketDir: URL {
        if let envValue = env(EnvKey.socketDir), !envValue.isEmpty {
            return URL(fileURLWithPath: envValue)
        }

        // Default: /tmp/zellij-{uid}/
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

    /// Detect Zellij availability. Call once at startup.
    func detectZellijAvailability() async {
        guard !detectionComplete else { return }

        logger.info("Detecting Zellij availability...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [zellijPath, "--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                zellijVersion = output
                zellijAvailable = true
                logger.info("Zellij detected: \(output ?? "unknown version")")
            } else {
                zellijAvailable = false
                logger.info("Zellij not available (exit code: \(process.terminationStatus))")
            }
        } catch {
            zellijAvailable = false
            logger.warning("Zellij detection failed: \(error.localizedDescription)")
        }

        detectionComplete = true
    }

    /// Reset detection state (for testing).
    func resetDetection() {
        detectionComplete = false
        zellijAvailable = false
        zellijVersion = nil
    }

    // MARK: - Setters (for UI preferences)

    /// Set the session backend type.
    func setBackend(_ type: SessionBackendType) {
        UserDefaults.standard.set(type.rawValue, forKey: DefaultsKey.backend)
        logger.info("Session backend set to: \(type.rawValue)")
    }

    /// Set whether session restore is enabled.
    func setRestoreEnabled(_ enabled: Bool) {
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
    func validate() async -> [ConfigurationError] {
        var errors: [ConfigurationError] = []

        // If Zellij backend is requested, ensure it's available
        if backend == .zellij && !zellijAvailable {
            // Check if explicitly requested via env var
            if env(EnvKey.backend)?.lowercased() == "zellij" {
                errors.append(.zellijNotAvailable(
                    "Zellij backend requested but not available at path: \(zellijPath)"
                ))
            }
        }

        // Validate socket directory exists (if using Zellij)
        if backend == .zellij && zellijAvailable {
            let socketDirPath = socketDir.path
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: socketDirPath, isDirectory: &isDir) {
                // Socket dir may not exist yet - Zellij creates it
                logger.debug("Socket directory does not exist yet: \(socketDirPath)")
            }
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
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .zellijNotAvailable(let message):
            return "Zellij not available: \(message)"
        case .invalidSocketDir(let message):
            return "Invalid socket directory: \(message)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        }
    }
}

// MARK: - Debug Description

extension SessionConfiguration: CustomDebugStringConvertible {
    nonisolated var debugDescription: String {
        // Note: This is a simplified description for logging
        // Full state access requires @MainActor
        return "SessionConfiguration()"
    }
}
