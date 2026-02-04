import Foundation
@testable import AgentStudio

/// Mock process executor for testing ZellijService
final class MockProcessExecutor: ProcessExecutor, @unchecked Sendable {
    /// Responses keyed by command pattern
    private var responses: [String: ProcessResult] = [:]

    /// Simulated delays for commands (in seconds) - used to test timeouts
    private var delays: [String: TimeInterval] = [:]

    /// Record of all executed commands
    private(set) var executedCommands: [[String]] = []

    func execute(_ path: String, arguments: [String], timeout: TimeInterval?) async -> ProcessResult {
        executedCommands.append([path] + arguments)

        // Build key from command name + arguments
        let cmdName = URL(fileURLWithPath: path).lastPathComponent
        let fullCommand = ([cmdName] + arguments).joined(separator: " ")

        // Check for simulated delay (timeout testing)
        if let delay = findDelay(for: fullCommand) {
            if let timeout = timeout, delay > timeout {
                // Simulate timeout - wait for timeout duration then return timeout result
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return ProcessResult(
                    exitCode: -1,
                    stdout: "",
                    stderr: "Process timed out after \(Int(timeout)) seconds",
                    timedOut: true
                )
            }
            // Wait for the delay
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        // Try exact match first
        if let response = responses[fullCommand] {
            return response
        }

        // Try partial matches
        for (pattern, response) in responses {
            if fullCommand.contains(pattern) {
                return response
            }
        }

        // Default: command not mocked
        return ProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "Command not mocked: \(fullCommand)"
        )
    }

    /// Set up a successful response for a command pattern
    func mockSuccess(_ pattern: String, stdout: String = "") {
        responses[pattern] = ProcessResult(exitCode: 0, stdout: stdout, stderr: "")
    }

    /// Set up a failure response for a command pattern
    func mockFailure(_ pattern: String, stderr: String) {
        responses[pattern] = ProcessResult(exitCode: 1, stdout: "", stderr: stderr)
    }

    /// Set up a command that will timeout if called with a timeout shorter than delay
    func mockTimeout(_ pattern: String, delay: TimeInterval) {
        delays[pattern] = delay
        // No response needed - timeout will trigger before response lookup
    }

    /// Reset state between tests
    func reset() {
        responses.removeAll()
        executedCommands.removeAll()
        delays.removeAll()
    }

    /// Check if a command matching the pattern was executed
    func wasExecuted(_ pattern: String) -> Bool {
        executedCommands.contains { cmd in
            cmd.joined(separator: " ").contains(pattern)
        }
    }

    /// Find configured delay for a command
    private func findDelay(for command: String) -> TimeInterval? {
        for (pattern, delay) in delays {
            if command.contains(pattern) {
                return delay
            }
        }
        return nil
    }
}
