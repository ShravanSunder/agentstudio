import Foundation

/// Result of running an external process
struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool

    var succeeded: Bool { exitCode == 0 && !timedOut }

    init(exitCode: Int32, stdout: String, stderr: String, timedOut: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

/// Protocol for executing external processes (enables mocking in tests)
protocol ProcessExecutor: Sendable {
    /// Execute a process with optional timeout
    /// - Parameters:
    ///   - path: Path to executable
    ///   - arguments: Command arguments
    ///   - timeout: Timeout in seconds (nil for no timeout)
    /// - Returns: ProcessResult with exit code, output, and timeout status
    func execute(_ path: String, arguments: [String], timeout: TimeInterval?) async -> ProcessResult
}

/// Extension providing default timeout for backward compatibility
extension ProcessExecutor {
    func execute(_ path: String, arguments: [String]) async -> ProcessResult {
        await execute(path, arguments: arguments, timeout: 30.0)
    }
}

/// Real implementation that runs actual processes
struct RealProcessExecutor: ProcessExecutor {
    func execute(_ path: String, arguments: [String], timeout: TimeInterval?) async -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        // Inherit current environment + add TERM for CLI tools like Zellij
        // Without TERM, many CLI tools (especially terminal multiplexers) hang or behave incorrectly
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice  // Prevent stdin blocking

        do {
            try process.run()
        } catch {
            return ProcessResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        // No timeout case - simple blocking wait
        guard let timeout = timeout else {
            process.waitUntilExit()
            return readResult(process: process, stdout: stdoutPipe, stderr: stderrPipe, timedOut: false)
        }

        // With timeout: race between process completion and timeout
        // Use an actor-like class to safely coordinate continuation resumption
        let coordinator = ProcessCoordinator(
            process: process,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe,
            timeout: timeout
        )
        return await coordinator.run()
    }

    private func readResult(process: Process, stdout: Pipe, stderr: Pipe, timedOut: Bool) -> ProcessResult {
        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            timedOut: timedOut
        )
    }
}

/// Coordinator for process execution with timeout
/// Uses class with lock for thread-safe continuation management
private final class ProcessCoordinator: @unchecked Sendable {
    private let process: Process
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var hasResumed = false

    init(process: Process, stdoutPipe: Pipe, stderrPipe: Pipe, timeout: TimeInterval) {
        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.timeout = timeout
    }

    func run() async -> ProcessResult {
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "processExecutor.\(UUID().uuidString)")

            // Timeout handler
            let timeoutWorkItem = DispatchWorkItem { [self] in
                lock.lock()
                defer { lock.unlock() }

                guard !hasResumed else { return }
                hasResumed = true

                // Terminate the process
                if process.isRunning {
                    process.terminate()
                    // Give it a moment to clean up, then force interrupt
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [self] in
                        if process.isRunning {
                            process.interrupt()
                        }
                    }
                }

                let result = ProcessResult(
                    exitCode: -1,
                    stdout: "",
                    stderr: "Process timed out after \(Int(timeout)) seconds",
                    timedOut: true
                )
                continuation.resume(returning: result)
            }

            queue.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

            // Process completion handler
            process.terminationHandler = { [self] terminatedProcess in
                lock.lock()
                defer { lock.unlock() }

                guard !hasResumed else { return }
                hasResumed = true

                timeoutWorkItem.cancel()

                let result = readResult(process: terminatedProcess)
                continuation.resume(returning: result)
            }
        }
    }

    private func readResult(process: Process) -> ProcessResult {
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            timedOut: false
        )
    }
}
