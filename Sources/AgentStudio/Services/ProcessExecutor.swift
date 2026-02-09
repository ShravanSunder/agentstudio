import Foundation
import os

private let processLogger = Logger(subsystem: "com.agentstudio", category: "ProcessExecutor")

// MARK: - ProcessExecutor Protocol

/// Testable wrapper for CLI execution. In production, runs Process.
/// In tests, returns canned responses.
protocol ProcessExecutor: Sendable {
    func execute(
        command: String,
        args: [String],
        cwd: URL?,
        environment: [String: String]?
    ) async throws -> ProcessResult
}

/// Result of a CLI command execution.
struct ProcessResult: Sendable {
    let exitCode: Int
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

// MARK: - ProcessError

enum ProcessError: Error, LocalizedError {
    case timedOut(command: String, seconds: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .timedOut(let command, let seconds):
            return "Process '\(command)' timed out after \(Int(seconds))s"
        }
    }
}

// MARK: - DefaultProcessExecutor

/// Production executor that spawns real processes on a background thread.
///
/// Blocking Foundation calls (`readDataToEndOfFile`, `waitUntilExit`) are
/// dispatched to `DispatchQueue.global()` so they never block the MainActor.
/// A configurable timeout terminates hung processes.
struct DefaultProcessExecutor: ProcessExecutor {
    /// Default timeout for process execution.
    let timeout: TimeInterval

    init(timeout: TimeInterval = 15) {
        self.timeout = timeout
    }

    func execute(
        command: String,
        args: [String],
        cwd: URL?,
        environment: [String: String]?
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args

        if let cwd {
            process.currentDirectoryURL = cwd
        }

        // Merge provided environment with inherited, ensuring brew paths
        var env = ProcessInfo.processInfo.environment
        if let override = environment {
            env.merge(override) { _, new in new }
        }
        if let path = env["PATH"] {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(path)"
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Track whether our timeout killed the process (vs. normal exit/other signal).
        let timedOut = LockedFlag()

        // Schedule a timeout that terminates the process if it hangs.
        let timeoutSeconds = timeout
        let timeoutWork = DispatchWorkItem { [process] in
            if process.isRunning {
                processLogger.warning("Process '\(command)' exceeded \(Int(timeoutSeconds))s timeout — terminating")
                timedOut.set()
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(
            deadline: .now() + timeoutSeconds,
            execute: timeoutWork
        )

        // Offload blocking I/O to a background thread so the MainActor is never blocked.
        let result: ProcessResult = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Read pipes FIRST to prevent buffer deadlock.
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                // Safe to call waitUntilExit() now — pipes are fully drained.
                process.waitUntilExit()

                // Cancel the timeout since the process exited.
                timeoutWork.cancel()

                // Use our flag to detect timeout (more reliable than exit code matching).
                if timedOut.value {
                    continuation.resume(throwing: ProcessError.timedOut(
                        command: command, seconds: timeoutSeconds
                    ))
                    return
                }

                continuation.resume(returning: ProcessResult(
                    exitCode: Int(process.terminationStatus),
                    stdout: String(data: stdoutData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                ))
            }
        }

        return result
    }
}

// MARK: - LockedFlag

/// Thread-safe boolean flag for cross-thread signaling (e.g. timeout detection).
final class LockedFlag: @unchecked Sendable {
    private var _value = false
    private let lock = NSLock()

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func set() {
        lock.lock()
        _value = true
        lock.unlock()
    }
}
