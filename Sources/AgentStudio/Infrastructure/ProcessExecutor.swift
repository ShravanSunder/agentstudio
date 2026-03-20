import Darwin
@preconcurrency import Dispatch
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

    private static let defaultSystemPath = "/usr/bin:/bin:/usr/sbin:/sbin"
    private static let toolchainPathPrefix = "/opt/homebrew/bin:/usr/local/bin"

    private static func normalizedEnvironment(from environment: [String: String]) -> [String: String] {
        var env = environment

        let inheritedPath = env["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let basePath =
            (inheritedPath?.isEmpty == false) ? inheritedPath! : Self.defaultSystemPath
        env["PATH"] = "\(Self.toolchainPathPrefix):\(basePath)"

        let inheritedHome = env["HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if inheritedHome?.isEmpty != false {
            env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        }

        return env
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
        // and HOME are available for CLI tools (gh auth config lookup).
        var env = ProcessInfo.processInfo.environment
        if let override = environment {
            env.merge(override) { _, new in new }
        }
        process.environment = Self.normalizedEnvironment(from: env)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBuffer = LockedDataBuffer()
        let stderrBuffer = LockedDataBuffer()

        let (terminationStream, terminationContinuation) = AsyncStream.makeStream(of: Int32.self)
        let (stdoutEOFStream, stdoutEOFContinuation) = AsyncStream.makeStream(of: Void.self)
        let (stderrEOFStream, stderrEOFContinuation) = AsyncStream.makeStream(of: Void.self)

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                stdoutEOFContinuation.yield(())
                stdoutEOFContinuation.finish()
                return
            }
            stdoutBuffer.append(chunk)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                stderrEOFContinuation.yield(())
                stderrEOFContinuation.finish()
                return
            }
            stderrBuffer.append(chunk)
        }

        process.terminationHandler = { terminatedProcess in
            terminationContinuation.yield(terminatedProcess.terminationStatus)
            terminationContinuation.finish()
        }

        try process.run()

        // Track whether our timeout killed the process (vs. normal exit/other signal).
        let timedOut = LockedFlag()

        // Schedule a timeout that terminates the process if it hangs.
        let timeoutSeconds = timeout
        let hardKillGraceSeconds: TimeInterval = 0.2
        let timeoutTask = Task { [process] in
            do {
                try await Task.sleep(for: .seconds(timeoutSeconds))
            } catch {
                return
            }

            guard process.isRunning else { return }
            processLogger.warning("Process '\(command)' exceeded \(Int(timeoutSeconds))s timeout — terminating")
            timedOut.set()
            process.terminate()

            do {
                try await Task.sleep(for: .seconds(hardKillGraceSeconds))
            } catch {
                return
            }

            guard process.isRunning else { return }
            processLogger.warning(
                "Process '\(command)' ignored terminate() after \(hardKillGraceSeconds, privacy: .public)s — forcing SIGKILL"
            )
            let pid = process.processIdentifier
            if pid > 0 {
                _ = kill(pid, SIGKILL)
            }
        }

        var terminationIterator = terminationStream.makeAsyncIterator()
        var stdoutEOFIterator = stdoutEOFStream.makeAsyncIterator()
        var stderrEOFIterator = stderrEOFStream.makeAsyncIterator()

        let terminationStatus = await terminationIterator.next()
        timeoutTask.cancel()

        _ = await stdoutEOFIterator.next()
        _ = await stderrEOFIterator.next()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        guard let terminationStatus else {
            throw ProcessError.timedOut(command: command, seconds: timeoutSeconds)
        }

        if timedOut.value {
            throw ProcessError.timedOut(command: command, seconds: timeoutSeconds)
        }

        return ProcessResult(
            exitCode: Int(terminationStatus),
            stdout: stdoutBuffer.utf8String,
            stderr: stderrBuffer.utf8String
        )
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

final class LockedDataBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var utf8String: String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return String(data: snapshot, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
