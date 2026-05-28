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

/// Production executor that spawns real processes and reports completion asynchronously.
///
/// The implementation keeps process lifecycle out of `AsyncStream` and task-group races.
/// Dispatch sources/handlers drive pipe reads, process exit, timeout, and cancellation;
/// one checked continuation is resumed exactly once.
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

        let execution = ProcessExecution(
            command: command,
            process: process,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe,
            timeoutSeconds: timeout,
            hardKillGraceSeconds: 0.2
        )
        return try await execution.run()
    }

    fileprivate static func decodeAndTrim(_ data: Data) -> String {
        (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class ProcessExecution: @unchecked Sendable {
    private typealias Continuation = CheckedContinuation<ProcessResult, Error>

    private enum PipeKind {
        case stdout
        case stderr
    }

    private let command: String
    private let process: Process
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe
    private let timeoutSeconds: TimeInterval
    private let hardKillGraceSeconds: TimeInterval
    private let queue: DispatchQueue
    private let lock = NSLock()

    private var continuation: Continuation?
    private var stdoutData = Data()
    private var stderrData = Data()
    private var processExited = false
    private var stdoutFinished = false
    private var stderrFinished = false
    private var terminationStatus: Int32 = 0
    private var didTimeout = false
    private var cancelRequested = false
    private var completed = false
    private var processSource: DispatchSourceProcess?
    private var stdoutSource: DispatchSourceRead?
    private var stderrSource: DispatchSourceRead?
    private var timeoutSource: DispatchSourceTimer?

    init(
        command: String,
        process: Process,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        timeoutSeconds: TimeInterval,
        hardKillGraceSeconds: TimeInterval
    ) {
        self.command = command
        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.timeoutSeconds = timeoutSeconds
        self.hardKillGraceSeconds = hardKillGraceSeconds
        queue = DispatchQueue(label: "com.agentstudio.process-executor.\(UUID().uuidString)", qos: .userInitiated)
    }

    func run() async throws -> ProcessResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    self.start(continuation)
                }
            }
        } onCancel: {
            cancel()
        }
    }

    private func start(_ continuation: Continuation) {
        let shouldCancel = installContinuation(continuation)
        guard !shouldCancel else {
            complete(.failure(CancellationError()))
            return
        }

        configureTerminationHandler()

        do {
            try process.run()
        } catch {
            complete(.failure(error))
            return
        }

        configurePipeSources()
        configureProcessSource()
        configureTimeoutSource()
        stdoutSource?.resume()
        stderrSource?.resume()
        processSource?.resume()
        timeoutSource?.resume()
    }

    private func installContinuation(_ continuation: Continuation) -> Bool {
        lock.lock()
        self.continuation = continuation
        let shouldCancel = cancelRequested
        lock.unlock()
        return shouldCancel
    }

    private func configurePipeSources() {
        stdoutSource = makeReadSource(pipe: stdoutPipe, kind: .stdout)
        stderrSource = makeReadSource(pipe: stderrPipe, kind: .stderr)
    }

    private func makeReadSource(pipe: Pipe, kind: PipeKind) -> DispatchSourceRead {
        let fileHandle = pipe.fileHandleForReading
        let source = DispatchSource.makeReadSource(fileDescriptor: fileHandle.fileDescriptor, queue: queue)
        source.setEventHandler { [self, fileHandle] in
            let chunk = fileHandle.availableData
            if chunk.isEmpty {
                markPipeFinished(kind)
            } else {
                append(chunk, from: kind)
            }
        }
        source.setCancelHandler { [fileHandle] in
            try? fileHandle.close()
        }
        return source
    }

    private func configureTerminationHandler() {
        process.terminationHandler = { [weak self] terminatedProcess in
            guard let execution = self else { return }
            let status = terminatedProcess.terminationStatus
            execution.queue.async {
                execution.markProcessExited(status: status)
            }
        }
    }

    private func configureProcessSource() {
        let source = DispatchSource.makeProcessSource(
            identifier: process.processIdentifier,
            eventMask: .exit,
            queue: queue
        )
        source.setEventHandler { [self] in
            // DispatchSourceProcess is a wakeup/backstop; Foundation's
            // terminationHandler owns the status because terminationStatus can
            // still throw if the source fires before Process marks itself exited.
            guard !process.isRunning else { return }
            markProcessExited(status: process.terminationStatus)
        }
        processSource = source
    }

    private func configureTimeoutSource() {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + timeoutSeconds)
        source.setEventHandler { [self] in
            markTimedOut()
        }
        timeoutSource = source
    }

    private func append(_ data: Data, from kind: PipeKind) {
        lock.lock()
        switch kind {
        case .stdout:
            stdoutData.append(data)
        case .stderr:
            stderrData.append(data)
        }
        lock.unlock()
    }

    private func markPipeFinished(_ kind: PipeKind) {
        switch kind {
        case .stdout:
            stdoutSource?.cancel()
        case .stderr:
            stderrSource?.cancel()
        }

        var completion: Result<ProcessResult, Error>?
        lock.lock()
        switch kind {
        case .stdout:
            stdoutFinished = true
        case .stderr:
            stderrFinished = true
        }
        completion = completionIfReadyLocked()
        lock.unlock()

        if let completion {
            complete(completion)
        }
    }

    private func markProcessExited(status: Int32) {
        var completion: Result<ProcessResult, Error>?
        lock.lock()
        processExited = true
        terminationStatus = status
        completion = completionIfReadyLocked()
        lock.unlock()

        if let completion {
            complete(completion)
        }
    }

    private func markTimedOut() {
        let shouldTerminate: Bool
        lock.lock()
        if completed || didTimeout {
            shouldTerminate = false
        } else {
            didTimeout = true
            shouldTerminate = true
        }
        lock.unlock()

        guard shouldTerminate else { return }
        processLogger.warning(
            "Process '\(self.command, privacy: .public)' exceeded \(Int(self.timeoutSeconds))s timeout - terminating"
        )
        if self.process.isRunning {
            self.process.terminate()
        }
        queue.asyncAfter(deadline: .now() + self.hardKillGraceSeconds) { [self] in
            forceKillIfStillRunning()
        }
    }

    private func forceKillIfStillRunning() {
        guard self.process.isRunning else { return }
        processLogger.warning(
            "Process '\(self.command, privacy: .public)' ignored terminate() after \(self.hardKillGraceSeconds, privacy: .public)s - forcing SIGKILL"
        )
        let pid = self.process.processIdentifier
        if pid > 0 {
            _ = kill(pid, SIGKILL)
        }
    }

    private func completionIfReadyLocked() -> Result<ProcessResult, Error>? {
        guard processExited, stdoutFinished, stderrFinished else {
            return nil
        }
        if didTimeout {
            return .failure(ProcessError.timedOut(command: command, seconds: timeoutSeconds))
        }
        let result = ProcessResult(
            exitCode: Int(terminationStatus),
            stdout: DefaultProcessExecutor.decodeAndTrim(stdoutData),
            stderr: DefaultProcessExecutor.decodeAndTrim(stderrData)
        )
        return .success(result)
    }

    private func cancel() {
        var shouldTerminate = false
        var continuationToResume: Continuation?

        lock.lock()
        cancelRequested = true
        if !completed, let continuation {
            completed = true
            continuationToResume = continuation
            self.continuation = nil
            shouldTerminate = true
        }
        lock.unlock()

        if shouldTerminate {
            terminateForCancellation()
            cleanupSources()
        }
        continuationToResume?.resume(throwing: CancellationError())
    }

    private func terminateForCancellation() {
        guard process.isRunning else { return }
        process.terminate()
        queue.asyncAfter(deadline: .now() + hardKillGraceSeconds) { [self] in
            forceKillIfStillRunning()
        }
    }

    private func complete(_ result: Result<ProcessResult, Error>) {
        let continuationToResume: Continuation?
        lock.lock()
        if completed {
            lock.unlock()
            return
        }
        completed = true
        continuationToResume = continuation
        continuation = nil
        lock.unlock()

        cleanupSources()
        continuationToResume?.resume(with: result)
    }

    private func cleanupSources() {
        process.terminationHandler = nil
        timeoutSource?.cancel()
        processSource?.cancel()
        stdoutSource?.cancel()
        stderrSource?.cancel()
        timeoutSource = nil
        processSource = nil
        stdoutSource = nil
        stderrSource = nil
    }
}
