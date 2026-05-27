import Darwin
import Dispatch
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

        try process.run()

        let timeoutSeconds = timeout
        let hardKillGraceSeconds: TimeInterval = 0.2

        // Race the process's wait+read against a sleep timer.
        // Avoids withCheckedThrowingContinuation (swift#84793) and AsyncStream
        // continuations yielded from libdispatch handlers (foundation#3276).
        return try await withThrowingTaskGroup(of: ExecutionOutcome.self) { group in
            group.addTask {
                await Self.waitAndReadAll(
                    process: process,
                    stdoutPipe: stdoutPipe,
                    stderrPipe: stderrPipe
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                return .timedOut
            }

            guard let first = try await group.next() else {
                throw ProcessError.timedOut(command: command, seconds: timeoutSeconds)
            }
            group.cancelAll()

            switch first {
            case .completed(let exitCode, let stdoutData, let stderrData):
                return ProcessResult(
                    exitCode: Int(exitCode),
                    stdout: Self.decodeAndTrim(stdoutData),
                    stderr: Self.decodeAndTrim(stderrData)
                )
            case .timedOut:
                processLogger.warning(
                    "Process '\(command, privacy: .public)' exceeded \(Int(timeoutSeconds))s timeout — terminating"
                )
                if process.isRunning {
                    process.terminate()
                }
                try? await Task.sleep(for: .seconds(hardKillGraceSeconds))
                if process.isRunning {
                    processLogger.warning(
                        "Process '\(command, privacy: .public)' ignored terminate() after \(hardKillGraceSeconds, privacy: .public)s — forcing SIGKILL"
                    )
                    let pid = process.processIdentifier
                    if pid > 0 {
                        _ = kill(pid, SIGKILL)
                    }
                }
                throw ProcessError.timedOut(command: command, seconds: timeoutSeconds)
            }
        }
    }

    private enum ExecutionOutcome: Sendable {
        case completed(exitCode: Int32, stdout: Data, stderr: Data)
        case timedOut
    }

    /// Blocks the calling thread on `waitUntilExit()` and drains both pipes
    /// concurrently via libdispatch reads. Must run off the caller's executor;
    /// `@concurrent` forces escape to the global concurrent executor per SE-0461.
    @concurrent
    nonisolated private static func waitAndReadAll(
        process: Process,
        stdoutPipe: Pipe,
        stderrPipe: Pipe
    ) async -> ExecutionOutcome {
        let stdoutBuffer = ReadBuffer()
        let stderrBuffer = ReadBuffer()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdoutBuffer.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderrBuffer.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        process.waitUntilExit()
        group.wait()

        return .completed(
            exitCode: process.terminationStatus,
            stdout: stdoutBuffer.data,
            stderr: stderrBuffer.data
        )
    }

    private static func decodeAndTrim(_ data: Data) -> String {
        (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Synchronization handoff for pipe-drain DispatchQueue blocks. The DispatchGroup
/// provides happens-before between the writer and reader, so plain unchecked
/// Sendable is correct here.
private final class ReadBuffer: @unchecked Sendable {
    var data = Data()
}
